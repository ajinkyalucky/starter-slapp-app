'use strict'

const express = require('express')
const path = require('path')

const app = express()
const port = process.env.PORT || 3000

app.use(express.json())
app.use(express.static(path.join(__dirname, 'public')))

// Mock catalog data so the UI can be driven by an API call
const LOOKS = {
  work: {
    tagline: "A sharp boardroom look — refined lines, modern neutrals.",
    fitScore: 92,
    items: [
      { id: 'w1', name: 'Charcoal Wool Suit',     price: 18999, stock: 'In Stock',     left: 2, img: 'blazer' },
      { id: 'w2', name: 'Crisp White Shirt',      price: 2299,  stock: 'In Stock',     left: 5, img: 'shirt'  },
      { id: 'w3', name: 'Slim Wool Trousers',     price: 4999,  stock: 'In Stock',     left: 3, img: 'pants'  },
      { id: 'w4', name: 'Leather Oxford Shoes',   price: 6499,  stock: 'Low Stock',    left: 1, img: 'shoes'  },
      { id: 'w5', name: 'Slim Tie',               price: 1299,  stock: 'In Stock',     left: 4, img: 'watch'  }
    ],
    badges: ['Authoritative', 'Modern Tailoring', 'Boardroom ready', 'Slim silhouette', 'Trending in Mumbai']
  },
  date: {
    tagline: "Here's a look curated for you, based on your style, fit & trends.",
    fitScore: 94,
    items: [
      { id: 'd1', name: 'Linen Blend Blazer',     price: 8499,  stock: 'In Stock', left: 2, img: 'blazer' },
      { id: 'd2', name: 'Premium Cotton Tee',     price: 1899,  stock: 'In Stock', left: 3, img: 'shirt'  },
      { id: 'd3', name: 'Tailored Trousers',      price: 3999,  stock: 'In Stock', left: 2, img: 'pants'  },
      { id: 'd4', name: 'Minimal White Sneakers', price: 4299,  stock: 'In Stock', left: 4, img: 'shoes'  },
      { id: 'd5', name: 'Chronograph Watch',      price: 12499, stock: 'In Stock', left: 1, img: 'watch'  }
    ],
    badges: ['Sharp jawline fit', 'V-shape silhouette', 'Broad shoulder enhancement', 'Perfect for Date / Evening', 'Trending in Bangalore']
  },
  casual: {
    tagline: "Easy weekend energy — light layers, comfortable flow.",
    fitScore: 89,
    items: [
      { id: 'c1', name: 'Oversized Hoodie',       price: 2799,  stock: 'In Stock',  left: 6, img: 'blazer' },
      { id: 'c2', name: 'Graphic Cotton Tee',     price: 1199,  stock: 'In Stock',  left: 8, img: 'shirt'  },
      { id: 'c3', name: 'Relaxed Denim',          price: 3299,  stock: 'In Stock',  left: 4, img: 'pants'  },
      { id: 'c4', name: 'Canvas Sneakers',        price: 2199,  stock: 'In Stock',  left: 5, img: 'shoes'  },
      { id: 'c5', name: 'Beaded Bracelet Stack',  price: 899,   stock: 'In Stock',  left: 7, img: 'watch'  }
    ],
    badges: ['Relaxed fit', 'Movement friendly', 'Soft fabrics', 'Weekend ready', 'Trending in Goa']
  },
  travel: {
    tagline: "Wrinkle-resistant, lightweight, ready for 12-hour days.",
    fitScore: 91,
    items: [
      { id: 't1', name: 'Tech Bomber Jacket',     price: 6999,  stock: 'In Stock', left: 3, img: 'blazer' },
      { id: 't2', name: 'Merino Travel Tee',      price: 2499,  stock: 'In Stock', left: 4, img: 'shirt'  },
      { id: 't3', name: 'Stretch Cargo Pants',    price: 3799,  stock: 'In Stock', left: 5, img: 'pants'  },
      { id: 't4', name: 'Trail Runner Sneakers',  price: 5499,  stock: 'In Stock', left: 2, img: 'shoes'  },
      { id: 't5', name: 'GMT Field Watch',        price: 9999,  stock: 'Low Stock', left: 1, img: 'watch' }
    ],
    badges: ['Wrinkle resistant', 'Breathable', 'Layer ready', 'All-day comfort', 'Trending with travelers']
  }
}

app.get('/api/look/:category', (req, res) => {
  const cat = (req.params.category || '').toLowerCase()
  const look = LOOKS[cat]
  if (!look) return res.status(404).json({ error: 'category_not_found' })
  res.json({ category: cat, ...look })
})

app.post('/api/reserve', (req, res) => {
  const { items = [] } = req.body || {}
  const expiresAt = Date.now() + 30 * 60 * 1000
  res.json({
    ok: true,
    reservationId: 'RSV-' + Math.random().toString(36).slice(2, 8).toUpperCase(),
    items,
    expiresAt
  })
})

app.get('/healthz', (_, res) => res.json({ ok: true }))

app.listen(port, () => {
  console.log(`AI Stylist running on http://localhost:${port}`)
})
