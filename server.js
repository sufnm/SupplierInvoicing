import express from 'express';
import sql from 'mssql';
import cors from 'cors';
import dotenv from 'dotenv';

dotenv.config();

const app = express();
app.use(cors());
app.use(express.json());

// MSSQL connection configuration
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

let pool;

async function getPool() {
  if (pool) return pool;
  try {
    pool = await sql.connect(dbConfig);
    console.log('✅ Connected to MSSQL');
    return pool;
  } catch (err) {
    console.error('❌ Database connection failed:', err.message);
    throw err;
  }
}

// Item search endpoint with Last Purchase Price
app.get('/api/items/search', async (req, res) => {
  const { q } = req.query;
  // If no query, we'll return TOP 20 items anyway to show a list initially
  const searchQuery = q ? `%${q}%` : '%';

  try {
    const pool = await getPool();
    const result = await pool.request()
      .input('query', sql.VarChar, searchQuery)
      .query(`
        SELECT TOP 20 
          b.BARCODE, 
          b.DESCRIPTION,
          s.AVG_PUR_PRICE 
        FROM dbo.BARCODE b
        LEFT JOIN dbo.STOCK_MASTER s ON b.BARCODE = s.ITEM_CODE
        WHERE b.BARCODE LIKE @query OR b.DESCRIPTION LIKE @query
        ORDER BY b.DESCRIPTION ASC
      `);
    
    console.log(`🔍 Item Search: Found ${result.recordset.length} results`);
    res.json(result.recordset);
  } catch (error) {
    console.error("Item search failed:", error.message);
    res.status(500).json({ error: 'Database search error' });
  }
});

// Update item cost price endpoint
app.post('/api/items/update-price', async (req, res) => {
  const { itemCode, costPrice } = req.body;
  if (!itemCode || costPrice === undefined) {
    return res.status(400).json({ error: 'itemCode and costPrice are required' });
  }

  try {
    const pool = await getPool();
    await pool.request()
      .input('itemCode', sql.VarChar, itemCode)
      .input('costPrice', sql.Decimal(18, 2), costPrice)
      .query(`
        UPDATE dbo.STOCK_MASTER 
        SET LAST_PUR_PRICE = @costPrice 
        WHERE ITEM_CODE = @itemCode
      `);
    
    console.log(`✅ Updated LAST_PUR_PRICE for ${itemCode} to ${costPrice}`);
    res.json({ success: true });
  } catch (error) {
    console.error("Update price failed:", error.message);
    res.status(500).json({ error: 'Database update error' });
  }
});

// Supplier search endpoint
app.get('/api/suppliers/search', async (req, res) => {
  const { q } = req.query;
  try {
    const pool = await getPool();
    let query = `SELECT ACC_NO, ACC_NAME FROM dbo.ACCOUNTS_INFO WHERE ACC_TYPE = 2`;
    const request = pool.request();
    
    if (q) {
      request.input('query', sql.VarChar, `%${q}%`);
      query += ` AND (ACC_NAME LIKE @query OR ACC_NO LIKE @query)`;
    }
    
    const result = await request.query(query);
    console.log(`🔍 Supplier Search: Found ${result.recordset.length} results for query: "${q || ''}"`);
    res.json(result.recordset);
  } catch (error) {
    console.error("Supplier search failed:", error.message);
    res.status(500).json({ error: 'Database search error' });
  }
});

// Save Invoice with full schema logic
app.post('/api/sales/save', async (req, res) => {
  const invoice = req.body;
  const pool = await getPool();
  const transaction = new sql.Transaction(pool);

  try {
    await transaction.begin();

    // 1. Insert into DATA_ENTRY_WEB to trigger INVOICE_NO generation
    const webRequest = new sql.Request(transaction);
    const webResult = await webRequest
      .input('acCode', sql.VarChar, invoice.ACCODE)
      .input('eName', sql.VarChar, invoice.ENAME)
      .input('netAmount', sql.Decimal(18, 2), invoice.NET_AMOUNT)
      .input('trnType', sql.Int, 2)
      .input('refNo', sql.VarChar, invoice.REF_INV_NO || '')
      .query(`
        INSERT INTO dbo.DATA_ENTRY_WEB (ACCODE, ENAME, NET_AMOUNT, TRN_TYPE, CURDATE, REF_NO)
        VALUES (@acCode, @eName, @netAmount, @trnType, GETDATE(), @refNo);

        SELECT REC_NO, INVOICE_NO FROM dbo.DATA_ENTRY_WEB WHERE REC_NO = SCOPE_IDENTITY();
      `);
    
    const invoiceNo = webResult.recordset[0].INVOICE_NO;
    const recNo = webResult.recordset[0].REC_NO;

    // 2. Insert each individual item into dbo.GRID_ITEM
    let rowNum = 1;
    for (const row of invoice.ROWS) {
      const itemRequest = new sql.Request(transaction);
      await itemRequest
        .input('barcode', sql.VarChar, row.itemCode)
        .input('description', sql.VarChar, row.description)
        .input('qty', sql.Decimal(18, 2), row.qty)
        .input('price', sql.Decimal(18, 2), row.price)
        .input('total', sql.Decimal(18, 2), row.qty * row.price)
        .input('invoiceNo', sql.VarChar, invoiceNo)
        .input('rowNum', sql.Int, rowNum++)
        .input('recNo', sql.Int, recNo)
        .query(`
          INSERT INTO dbo.GRID_ITEM (BARCODE, DESCRIPTION, QTY, price, TOTAL, INVOICE_NO, ROWNUM, TRN_TYPE, REC_NO, UNIT, vat_percent, VAT_AMOUNT, WR_CODE)
          VALUES (
            @barcode, 
            @description, 
            @qty, 
            @price, 
            @total, 
            @invoiceNo, 
            @rowNum, 
            2, 
            @recNo, 
            COALESCE((SELECT TOP 1 UNIT FROM dbo.HD_ITEMMASTER WHERE ITEM_CODE = @barcode), 'PCS'),
            0,
            0,
            0
          )
        `);

    }

    await transaction.commit();
    console.log(`✅ Invoice Saved Successfully: ${invoiceNo}`);
    res.json({ success: true, INVOICE_NO: invoiceNo });
  } catch (error) {
    if (transaction) await transaction.rollback();
    console.error("Failed to save invoice:", error.message);
    res.status(500).json({ error: 'Failed to save invoice', details: error.message });
  }
});

// Get all items (preloads in-app memory cache)
app.get('/api/items/all', async (req, res) => {
  try {
    const pool = await getPool();
    const result = await pool.request().query(`
      SELECT b.BARCODE, b.DESCRIPTION, s.AVG_PUR_PRICE 
      FROM dbo.BARCODE b
      LEFT JOIN dbo.STOCK_MASTER s ON b.BARCODE = s.ITEM_CODE
      ORDER BY b.DESCRIPTION ASC
    `);
    console.log(`📦 Cache Preload: Found ${result.recordset.length} items`);
    res.json(result.recordset);
  } catch (error) {
    console.error("Failed to load all items:", error.message);
    res.status(500).json({ error: 'Database query error' });
  }
});

// Get invoice history list (only credit purchases, trn_type = 2)
app.get('/api/sales/history', async (req, res) => {
  try {
    const pool = await getPool();
    const result = await pool.request().query(`
      SELECT REC_NO, INVOICE_NO, ACCODE, ENAME, NET_AMOUNT, CURDATE, REF_NO 
      FROM dbo.DATA_ENTRY_WEB 
      WHERE TRN_TYPE = 2 
      ORDER BY REC_NO DESC
    `);
    res.json(result.recordset);
  } catch (error) {
    console.error("Failed to fetch history:", error.message);
    res.status(500).json({ error: 'Database query error' });
  }
});

// Get detailed items of a historical invoice
app.get('/api/sales/history/:invoiceNo', async (req, res) => {
  const { invoiceNo } = req.params;
  try {
    const pool = await getPool();
    const result = await pool.request()
      .input('invoiceNo', sql.VarChar, invoiceNo)
      .query(`
        SELECT BARCODE, DESCRIPTION, QTY, price, TOTAL, ROWNUM, UNIT 
        FROM dbo.GRID_ITEM 
        WHERE INVOICE_NO = @invoiceNo AND TRN_TYPE = 2
        ORDER BY ROWNUM ASC
      `);
    res.json(result.recordset);
  } catch (error) {
    console.error("Failed to fetch invoice items:", error.message);
    res.status(500).json({ error: 'Database query error' });
  }
});

const PORT = process.env.PORT || 3005;
app.listen(PORT, async () => {
  console.log(`🚀 Server running on port ${PORT}`);
});
