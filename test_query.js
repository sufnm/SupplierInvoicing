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
    const res = await pool.request().query(`
      SELECT ACC_NO, ACC_NAME 
      FROM dbo.ACCOUNTS_INFO 
      WHERE ACC_NO = (SELECT CAST(CASH_PUR_AC AS VARCHAR) FROM dbo.AC_OPTIONS WHERE ID = 1)
    `);
    console.log('Result:', res.recordset);
    
    // Also test querying items with VAT_PERCENT
    const res2 = await pool.request().query(`
      SELECT TOP 5 b.BARCODE, b.DESCRIPTION, s.LAST_PUR_PRICE, h.VAT_PERCENT
      FROM dbo.BARCODE b
      LEFT JOIN dbo.STOCK_MASTER s ON b.BARCODE = s.ITEM_CODE
      LEFT JOIN dbo.HD_ITEMMASTER h ON b.BARCODE = h.ITEM_CODE
    `);
    console.log('Items with VAT:', res2.recordset);

    await sql.close();
  } catch (err) {
    console.error(err);
  }
}
test();
