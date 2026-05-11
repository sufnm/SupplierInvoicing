import sql from 'mssql';
import dotenv from 'dotenv';

dotenv.config();

const dbConfig = {
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  server: process.env.DB_SERVER || process.env.DB_HOST,
  database: process.env.DB_NAME,
  options: {
    encrypt: false,
    trustServerCertificate: true,
  }
};

async function test() {
  try {
    const pool = await sql.connect(dbConfig);
    const cols = await pool.request().query(`
      SELECT COLUMN_NAME, DATA_TYPE 
      FROM INFORMATION_SCHEMA.COLUMNS 
      WHERE TABLE_NAME = 'DATA_ENTRY_WEB'
    `);
    const names = cols.recordset.map(c => c.COLUMN_NAME.toUpperCase());
    console.log('DATA_ENTRY_WEB columns:', names.join(', '));
    await sql.close();
  } catch (err) {
    console.error(err);
  }
}
test();
