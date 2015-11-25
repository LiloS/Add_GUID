use test

--Add column GUID to each table--
EXEC sp_MSforeachtable '
if not exists (select * from sys.columns 
				where object_id = object_id(''?'')
				and name = ''diagram_id'')
alter table ? ADD GUID uniqueidentifier NOT NULL DEFAULT NEWID()'

--Create temporary table with Primary Keys (in case of different PK Columns in each table)--
SELECT  i.name AS IndexName,
        OBJECT_NAME(ic.OBJECT_ID) AS TableName,
        COL_NAME(ic.OBJECT_ID,ic.column_id) AS ColumnName
into #tempPK
FROM    sys.indexes AS i INNER JOIN 
        sys.index_columns AS ic ON  i.OBJECT_ID = ic.OBJECT_ID
									AND i.index_id = ic.index_id
WHERE   i.is_primary_key = 1

--Create temporary table with Foreign Keys where referenced table column is Primary Key--
SELECT	f.name AS ForeignKey, OBJECT_NAME(f.parent_object_id) AS TableName,
		COL_NAME(fc.parent_object_id, fc.parent_column_id) AS ColumnName,
		OBJECT_NAME (f.referenced_object_id) AS ReferenceTableName,
		COL_NAME(fc.referenced_object_id, fc.referenced_column_id) AS ReferenceColumnName
into #temp
FROM	sys.foreign_keys AS f INNER JOIN 
		sys.foreign_key_columns AS fc ON f.OBJECT_ID = fc.constraint_object_id
		JOIN #tempPK as pk ON pk.TableName = OBJECT_NAME (f.referenced_object_id) 
							AND COL_NAME(fc.referenced_object_id, fc.referenced_column_id) = pk.ColumnName
--Loop through #temp--
BEGIN
declare 
@tableParent varchar(max),
@tableReferenced varchar(max),
@columnValues varchar(max),
@columnID varchar(max),
@foreignKey varchar(max),
@newColumnName varchar(max)

DECLARE FKs CURSOR LOCAL FOR (select TableName, ReferenceTableName, ColumnName, ReferenceColumnName, ForeignKey from #temp)
declare @sql nvarchar(max),
@sql2 nvarchar(max),
@sql4 nvarchar(max),
@sql3 nvarchar(max),
@sql6 nvarchar(max)

OPEN FKs
FETCH NEXT FROM FKs into @tableParent, @tableReferenced, @columnValues, @columnID, @foreignKey
WHILE @@FETCH_STATUS = 0
BEGIN
	set @newColumnName = @columnValues+'_'+@tableReferenced+'_'+@tableParent+'_GUID'

	--Add column to Parent table (ex. Values_Table_1_Table_2_GUID)--
	set @sql6 = 'ALTER TABLE '+@tableParent+'
		ADD  '+@newColumnName +' uniqueidentifier NOT NULL DEFAULT NEWID()'

	--Set values to Parent table column (ex. Values_Table_1_Table_2_GUID) equal to Referenced GUID column values--
	set @sql4 = 'update '+@tableParent+' set '+@newColumnName+'='+@tableReferenced+'.GUID
		from '+@tableReferenced+ ' join '+@tableParent+' on '+@tableParent+'.'
		+@columnValues+'='+@tableReferenced+'.'+@columnID

	--Add Foreign Key from GUID to Parent table column (ex. Values_Table_1_Table_2_GUID)--
	set @sql = 'ALTER TABLE '+@tableReferenced+'
		ADD CONSTRAINT '+@tableReferenced+@foreignKey+'_GUID UNIQUE (GUID)'

	set @sql2 = 'ALTER TABLE '+@tableParent+'
		ADD FOREIGN KEY ('+@newColumnName+')
		REFERENCES '+@tableReferenced+'(GUID)'

	--Drop Foreign Key from ID to Values--
	set @sql3 = 'ALTER TABLE '+@tableParent+'
		DROP CONSTRAINT '+@foreignKey

	EXEC sp_executeSQL @sql6
	EXEC sp_executeSQL @sql4
	EXEC sp_executeSQL @sql
	EXEC sp_executeSQL @sql2
	EXEC sp_executeSQL @sql3

    FETCH NEXT FROM FKs into @tableParent, @tableReferenced, @columnValues, @columnID, @foreignKey
END

CLOSE FKs
DEALLOCATE FKs
drop table #temp
END

--Drop Primary Key columns and set GUID column to be new Primary Key--
EXEC sp_MSforeachtable '
declare @sql nvarchar(max),
@sql2 nvarchar(max)
if not exists (select * from sys.columns 
				where object_id = object_id(''?'')
				and name = ''diagram_id'')
BEGIN
SELECT	@sql2 = ''alter table ? Drop column '' + ColumnName  + '';'',
		@sql = ''ALTER TABLE ? DROP CONSTRAINT '' + IndexName + '';''
			FROM #tempPK
			WHERE OBJECT_ID(TableName) = OBJECT_ID(''?'');

EXEC sp_executeSQL @sql
EXEC sp_executeSQL @sql2
alter table? ADD PRIMARY KEY(GUID)
END
'
drop table #tempPK