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

async function lookup() {
  try {
    const pool = await sql.connect(dbConfig);
    const res = await pool.request().query(`
      SELECT TOP 10 BARCODE, DESCRIPTION FROM dbo.BARCODE
    `);
    console.log('TOP 10 BARCODES:', res.recordset);
    await sql.close();
  } catch (err) {
    console.error(err);
  }
}
lookup();
