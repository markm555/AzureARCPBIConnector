[Version = "1.0.0"]
section AzureARC;

CID = "3306fb45-23c7-44cb-ab71-dbbad0457366";
SID = "";
SQLQuery = "resources | where type =~ 'microsoft.azurearcdata/sqlserverinstances'";
OSQuery = "resources | where type =~ 'Microsoft.HybridCompute/machines'";
DatabaseQuery = "resources | where type =~ 'microsoft.azurearcdata/sqlserverinstances/databases'";
url = "https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2021-03-01";


[DataSource.Kind="AzureARCKind", Publish="AzureARCPublish"]


// Individual shared entities

shared NavTable = () as table =>
    let
        source = #table({"Name", "Data", "ItemKind", "ItemName", "IsLeaf"}, {
            { "OS", ExpandJsonArrays(makeRequest(OSQuery)), "Table", "Table", true },
            { "SQL", ExpandJsonArrays(makeRequest(SQLQuery)), "Table", "Table", true },
            { "Database", ExpandJsonArrays(makeRequest(DatabaseQuery)), "Table", "Table", true }
        }),
        navTable = Table.ToNavigationTable(source, {"Name"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")
    in
        navTable;

// Expand JSON Arrays

/* shared GetStorageMode = () as text =>
    let
        options = {"Import", "DirectQuery"},
        prompt = "Select Storage Mode (Import or DirectQuery)",
        userChoice = if Extension.CurrentCredential()[#"Mode"] <> null then
            Extension.CurrentCredential()[#"Mode"]
        else
            "Import" // Default to Import if no mode is selected
    in
        if List.Contains(options, userChoice) then userChoice else "Import"; */

shared makeRequest = (query) =>
    let
        //mode = GetStorageMode(),
        body = Text.ToBinary("{""query"": """ & query & """}"),
        response = Web.Contents(url, [
            Headers = [
                #"Content-Type" = "application/json",
                #"Authorization" = "Bearer " & Extension.CurrentCredential()[access_token]
            ],
            Content = body
        ]),
        json = Json.Document(response),
        data = json[data],
        tableData = Table.FromList(data, Splitter.SplitByNothing(), null, null, ExtraValues.Error)
    in
        tableData;

shared ExpandJsonArrays = (table as table, optional suffix as text) =>
    let
        columnNames = Table.ColumnNames(table),
        expandedTable = List.Accumulate(columnNames, table, (state, currentColumn) =>
            let
                columnType = Value.Type(Table.Column(state, currentColumn){0}),
                expandedState = if Type.Is(columnType, type list) then
                    Table.ExpandListColumn(state, currentColumn)
                else if Type.Is(columnType, type record) then
                    Table.ExpandRecordColumn(state, currentColumn, Record.FieldNames(Table.Column(state, currentColumn){0}), List.Transform(Record.FieldNames(Table.Column(state, currentColumn){0}), each currentColumn & "." & _))
                else
                    state
            in
            expandedState
        ),
        // Remove "Column1_" prefix if it exists
        cleanedTable = Table.TransformColumnNames(expandedTable, each if Text.StartsWith(_, "Column1.") then Text.RemoveRange(_, 0, 8) else _)
    in
        if List.AnyTrue(List.Transform(Table.ColumnNames(cleanedTable), (col) => Type.Is(Value.Type(Table.Column(cleanedTable, col){0}), type list) or Type.Is(Value.Type(Table.Column(cleanedTable, col){0}), type record))) then
            @ExpandJsonArrays(cleanedTable, suffix)
        else
            cleanedTable;

AddComputerName = (expandedtbl as table) =>
    let
        // Apply the function to the initial table
        expandedColumns = ExpandJsonArrays(expandedtbl),

        // Function to extract machine name
        extractMachineName = (id) =>
            let
                parts = Text.Split(id, "/"),
                machine_name = parts{8}  // The machine name is the 9th part in the split string
            in
                machine_name,

        // Add new column 'id' with the extracted machine name
        addIdColumn = Table.AddColumn(expandedColumns, "Computer", each extractMachineName([id]))
    in
        addIdColumn;

shared Table.ToNavigationTable = (
    table as table,
    keyColumns as list,
    nameColumn as text,
    dataColumn as text,
    itemKindColumn as text,
    itemNameColumn as text,
    isLeafColumn as text
) as table =>
    let
        tableType = Value.Type(table),
        newTableType = Type.AddTableKey(tableType, keyColumns, true) meta 
        [
            NavigationTable.NameColumn = nameColumn, 
            NavigationTable.DataColumn = dataColumn,
            NavigationTable.ItemKindColumn = itemKindColumn, 
            Preview.DelayColumn = itemNameColumn, 
            NavigationTable.IsLeafColumn = isLeafColumn
        ],
        navigationTable = Value.ReplaceType(table, newTableType)
    in
        navigationTable;

// OAuth2 Flow
/* StartLogin = (resourceUrl, state, display) =>
    let
        client_id = CID,
        redirect_uri = "https://oauth.powerbi.com/views/oauthredirect.html",
        scope = "https://management.azure.com/.default",
        authorization_uri = "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
        loginUrl = authorization_uri & "?client_id=" & client_id & "&response_type=code&redirect_uri=" & Uri.EscapeDataString(redirect_uri) & "&scope=" & Uri.EscapeDataString(scope) & "&state=" & Uri.EscapeDataString(state)
    in
        [
            LoginUri = loginUrl,
            CallbackUri = redirect_uri,
            WindowHeight = 720,
            WindowWidth = 1024
        ];

FinishLogin = (context, callbackUri, state) =>
    let
        parts = Uri.Parts(callbackUri),
        code = parts[Query][code],
        redirect_uri = "https://oauth.powerbi.com/views/oauthredirect.html",
        token_uri = "https://login.microsoftonline.com/common/oauth2/v2.0/token",
        client_id = CID,
        client_secret = SID,
        body = Text.ToBinary("grant_type=authorization_code&client_id=" & client_id & "&code=" & code & "&redirect_uri=" & Uri.EscapeDataString(redirect_uri) & "&client_secret=" & client_secret),
        tokenResponse = Web.Contents(token_uri, [
            Headers = [#"Content-Type" = "application/x-www-form-urlencoded"],
            Content = body
        ]),
        tokenJson = Json.Document(tokenResponse)
    in
        tokenJson;

// Data Source Kind
AzureARCKind = [
    Authentication = [
        OAuth2 = [
            AuthorizationUri = "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
            TokenUri = "https://login.microsoftonline.com/common/oauth2/v2.0/token",
            RedirectUri = "https://oauth.powerbi.com/views/oauthredirect.html",
            ClientId = CID,
            ClientSecret = SID,
            Scope = "https://management.azure.com/.default",
            StartLogin = StartLogin,
            FinishLogin = FinishLogin,
            WindowTitle = "Sign in to Azure",
            WindowHeight = 720,
            WindowWidth = 1024
        ]
    ]
]; */

AzureARCKind = [
    Authentication = [
        Aad = [
            AuthorizationUri = "https://login.microsoftonline.com/common/oauth2/authorize",
            Resource = "https://management.azure.com/"
            //Scope = "https://management.azure.com/.default"
        ]
    ]
];

// Data Source Publishing Info
AzureARCPublish = [
    Beta = true,
    Category = "Other",
    ButtonText = { Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp") },
    LearnMoreUrl = "https://powerbi.microsoft.com/",
    SourceImage = AzureARCIcons,
    SourceTypeImage = AzureARCIcons
];

// Icons
AzureARCIcons = [
    Icon16 = { Extension.Contents("AzureARC16.png"), Extension.Contents("AzureARC20.png"), Extension.Contents("AzureARC24.png"), Extension.Contents("AzureARC32.png") },
    Icon32 = { Extension.Contents("AzureARC32.png"), Extension.Contents("AzureARC40.png"), Extension.Contents("AzureARC48.png"), Extension.Contents("AzureARC64.png") }
];