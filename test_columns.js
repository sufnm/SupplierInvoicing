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

async function check() {
  try {
    const pool = await sql.connect(dbConfig);
    console.log('✅ Connected to database');

    // Check AC_OPTIONS schema
    const acOptsColumns = await pool.request().query(`
      SELECT COLUMN_NAME, DATA_TYPE 
      FROM INFORMATION_SCHEMA.COLUMNS 
      WHERE TABLE_NAME = 'AC_OPTIONS'
    `);
    console.log('\n📋 AC_OPTIONS Columns:');
    console.log(acOptsColumns.recordset.map(c => `${c.COLUMN_NAME} (${c.DATA_TYPE})`).join(', '));

    const acOptsSample = await pool.request().query(`SELECT TOP 1 * FROM dbo.AC_OPTIONS`);
    console.log('\n🔍 AC_OPTIONS sample row:');
    console.log(acOptsSample.recordset[0]);

    // Check HD_ITEMMASTER schema
    const itemMasterColumns = await pool.request().query(`
      SELECT COLUMN_NAME, DATA_TYPE 
      FROM INFORMATION_SCHEMA.COLUMNS 
      WHERE TABLE_NAME = 'HD_ITEMMASTER'
    `);
    console.log('\n📋 HD_ITEMMASTER Columns:');
    const cols = itemMasterColumns.recordset.map(c => c.COLUMN_NAME.toUpperCase());
    console.log('Columns count:', cols.length);
    console.log('Does it contain VAT_PERCENT?', cols.includes('VAT_PERCENT'));
    console.log('Does it contain VAT?', cols.includes('VAT'));
    console.log('Vat-like columns:', cols.filter(c => c.includes('VAT') || c.includes('TAX') || c.includes('PERCENT')));

    const itemMasterSample = await pool.request().query(`SELECT TOP 1 * FROM dbo.HD_ITEMMASTER`);
    console.log('\n🔍 HD_ITEMMASTER sample row:');
    console.log(itemMasterSample.recordset[0]);

    await sql.close();
  } catch (err) {
    console.error('❌ Error:', err.message);
  }
}

check();
