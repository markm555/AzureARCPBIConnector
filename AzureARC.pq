//*******************************************************************************************************
//*******************************************************************************************************
// ***** Author: Mark Moore (Microsoft)
// ***** Description: This file contains the M code for the AzureARC connector .
// ***** Date: 2025-03-26
// ***** Version: 1.0.0
//*******************************************************************************************************
//*******************************************************************************************************


[Version = "1.0.0"]
section AzureARC;

// Define variables used throughout the connector
SQLQuery = "resources | where type =~ 'microsoft.azurearcdata/sqlserverinstances'";
OSQuery = "resources | where type =~ 'Microsoft.HybridCompute/machines'";
DatabaseQuery = "resources | where type =~ 'microsoft.azurearcdata/sqlserverinstances/databases'";
SQLMIQuery = "resources | where type =~ 'microsoft.sql/managedinstances'";
SQLMIDBQuery = "resources | where type =~ 'microsoft.sql/managedinstances/databases'";
AzureSQLDBQuery = "resources | where type =~ 'microsoft.sql/servers'";
AzureSQLDBQueryDB = "resources | where type =~ 'microsoft.sql/servers/databases'";
url = "https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2021-03-01";


// Metadata for the connector
[DataSource.Kind="AzureARCKind", Publish="AzureARCPublish"]


// Navigation table for the connector -- This is the only way I could get multiple tables to load within a sinlgle connector
// This and other helper functions can be found here: https://learn.microsoft.com/en-us/power-query/helper-functions


shared ARCSQL = () as table =>
    let
        source = #table({"Name", "Data", "ItemKind", "ItemName", "IsLeaf"}, {
            { "OS", AddComputerName(ExpandJsonArrays(makeRequest(OSQuery))), "Table", "Table", true },
            { "SQL", AddComputerName(ExpandJsonArrays(makeRequest(SQLQuery))), "Table", "Table", true },
            { "Database", AddComputerName(ExpandJsonArrays(makeRequest(DatabaseQuery))), "Table", "Table", true }
        }),
        navTable = Table.ToNavigationTable(source, {"Name"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")
    in
        navTable;


// This function is used to make the API request to Azure ARC.  It has one paramert which is the query to be executed again Azure Graph.
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

// This function is used to expand the JSON arrays returned from the API request
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
            
            

//This function is used to extract the machine name from the id field so that each table will have a machine name that can be used to join the tables together
AddComputerName = (expandedtbl as table) =>
    let
        // Apply the function to the initial table
        //expandedColumns = ExpandJsonArrays(expandedtbl),

        // Function to extract machine name
        extractMachineName = (id) =>
            let
                parts = Text.Split(id, "/"),
                machine_name = parts{8}  // The machine name is the 9th part in the split string
            in
                machine_name,

        // Add new column 'id' with the extracted machine name
        addIdColumn = Table.AddColumn(expandedtbl, "Computer", each extractMachineName([id]))
    in
        addIdColumn;

// This is the helper function that is used to create the navigation table
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


// I am using AAD Authentication which will allow me to use the current user's credentials to authenticate to Azure ARC
// This is the only way I could get the connector to work without requiring a service principal
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
