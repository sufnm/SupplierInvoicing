import sql from 'mssql';
import dotenv from 'dotenv';

dotenv.config();

const dbConfig = {
  user: 'sa',
  password: 'sa0101',
  server: 'cloudsrv.dyndns.org',
  database: 'Eazysoftdb',
  options: {
    encrypt: false,
    trustServerCertificate: true,
  }
};

async function test() {
  try {
    const pool = await sql.connect(dbConfig);
    console.log('Connected to MSSQL');

    // 1. Search for any table names containing "UNIT"
    const searchResult = await pool.request().query("SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME LIKE '%UNIT%'");
    console.log('Tables containing UNIT:', searchResult.recordset);

    // 2. Query top 10 rows from any matching tables
    const unitTables = searchResult.recordset.map(t => t.TABLE_NAME);
    for (const table of unitTables) {
      try {
        const rows = await pool.request().query("SELECT TOP 10 * FROM dbo.[" + table + "]");
        console.log("\n--- Top rows from " + table + " ---");
        console.log(rows.recordset);
      } catch (err) {
        console.log("Failed to read from table " + table + ":", err.message);
      }
    }

    await sql.close();
  } catch (err) {
    console.error('Error:', err);
  }
}

test();
