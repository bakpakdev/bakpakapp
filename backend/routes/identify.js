const express = require('express');
const multer = require('multer');
const Anthropic = require('@anthropic-ai/sdk');
const { protectSupabase } = require('../middleware/supabaseAuth');
const { identifyRateLimit } = require('../middleware/identifyRateLimit');

const router = express.Router();

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024 },
});

const ALLOWED_MEDIA = new Set(['image/jpeg', 'image/png', 'image/webp', 'image/gif']);
const MODEL = process.env.ANTHROPIC_MODEL || 'claude-sonnet-4-6';
const WEB_SEARCH_TOOL_TYPE = process.env.ANTHROPIC_WEB_SEARCH_TOOL || 'web_search_20260209';

const SYSTEM_PROMPT = `You are popup's clothing identification agent for a campus thrift marketplace.

You will receive one or more photos of a garment or accessory. Identify it, then use web_search when a logo, tag, silhouette, or distinctive design is visible but you are not fully certain of the brand or exact product. Search to confirm the brand, product line, and official color name. Do not search for generic unbranded basics unless a mark or unique design is visible.

Return ONLY valid JSON. No markdown, no commentary.

Success schema:
{
  "brand": string or null,
  "color": string or null,
  "garmentType": string or null,
  "title": string or null,
  "size": string or null,
  "condition": "new" | "like-new" | "good" | "fair" | null,
  "suggestedPrice": number or null,
  "suggestedPriceMin": number or null,
  "suggestedPriceMax": number or null,
  "confidence": "low" | "medium" | "high",
  "matchedProductName": string or null,
  "sourceUrls": string[],
  "department": "mens" | "womens" | "unisex" | null,
  "warningCode": "NO_BRAND" | null
}

Rules:
- You may receive multiple photos of the SAME item. Use every photo (tags, labels, wear, logos, silhouette).
- garmentType: short marketplace name (hoodie, jeans, t-shirt, sneakers, etc.).
- title: a short listing title (e.g. "Navy Nike hoodie"), or null if you cannot form one.
- color: dominant color; prefer official product color names when web search confirms them. Null if unclear.
- brand: null if no brand is visible or inferable. Then set warningCode to "NO_BRAND".
- size: from a tag/label if visible (S, M, 32, 10, One Size). Null if not readable — do not guess.
- condition: from visible wear. new = tags on; like-new = barely worn; good = light wear; fair = obvious wear. Null if you cannot tell.
- suggestedPriceMin / suggestedPriceMax: realistic campus thrift/resale range from web search (USD). Both required together when you have market data; otherwise null. Min must be less than or equal to max.
- suggestedPrice: optional midpoint within that range; null if unknown.
- matchedProductName: specific product if found (e.g. "Nike Dunk Low Panda"); otherwise null.
- sourceUrls: URLs you actually used from web search. Empty array if you did not search.
- confidence: high only when brand+type are clear or web-confirmed; low if guessing.

If the image is not clothing/footwear/accessories, or nothing wearable is visible, return ONLY:
{ "errorCode": "NO_GARMENT" }

If it is wearable but you cannot even name a garment type, return ONLY:
{ "errorCode": "AMBIGUOUS" }`;

function fail(res, status, code, message) {
  return res.status(status).json({ code, message });
}

function stripDataUrl(raw) {
  const text = String(raw || '').trim();
  const match = text.match(/^data:(image\/[a-zA-Z0-9.+-]+);base64,(.+)$/);
  if (match) return { mediaType: match[1], base64: match[2].replace(/\s/g, '') };
  return { mediaType: null, base64: text.replace(/\s/g, '') };
}

function extractImages(req) {
  const out = [];
  const files = [
    ...(Array.isArray(req.files) ? req.files : []),
    ...(req.file ? [req.file] : []),
  ];
  for (const file of files) {
    if (!file?.buffer) continue;
    out.push({
      mediaType: file.mimetype || 'image/jpeg',
      base64: file.buffer.toString('base64'),
    });
  }

  const body = req.body || {};
  const list = [];
  if (Array.isArray(body.images)) list.push(...body.images);
  if (Array.isArray(body.imageBase64s)) {
    for (const raw of body.imageBase64s) list.push({ imageBase64: raw, mediaType: body.mediaType });
  }
  if (body.imageBase64 || body.image || body.base64) {
    list.push({
      imageBase64: body.imageBase64 || body.image || body.base64,
      mediaType: body.mediaType,
    });
  }

  for (const item of list) {
    const raw = typeof item === 'string' ? item : item?.imageBase64 || item?.image || item?.base64;
    if (!raw) continue;
    const parsed = stripDataUrl(raw);
    out.push({
      mediaType: (typeof item === 'object' && item?.mediaType) || parsed.mediaType || 'image/jpeg',
      base64: parsed.base64,
    });
  }

  return out.slice(0, 5);
}

function collectSourceUrls(content) {
  const urls = new Set();
  for (const block of content || []) {
    if (block.type === 'web_search_tool_result') {
      const items = Array.isArray(block.content) ? block.content : [];
      for (const item of items) {
        if (item && typeof item.url === 'string' && item.url.startsWith('http')) {
          urls.add(item.url);
        }
      }
    }
    if (block.type === 'text' && Array.isArray(block.citations)) {
      for (const citation of block.citations) {
        if (citation?.url && String(citation.url).startsWith('http')) {
          urls.add(citation.url);
        }
      }
    }
  }
  return [...urls];
}

function lastTextBlock(content) {
  const texts = (content || [])
    .filter((block) => block.type === 'text' && typeof block.text === 'string')
    .map((block) => block.text.trim())
    .filter(Boolean);
  return texts.length ? texts[texts.length - 1] : '';
}

function parseModelJson(text) {
  if (!text) return null;
  let raw = text.trim();
  const fenced = raw.match(/```(?:json)?\s*([\s\S]*?)```/i);
  if (fenced) raw = fenced[1].trim();
  const start = raw.indexOf('{');
  const end = raw.lastIndexOf('}');
  if (start === -1 || end === -1 || end <= start) return null;
  try {
    return JSON.parse(raw.slice(start, end + 1));
  } catch {
    return null;
  }
}

function normalizeConfidence(value) {
  const v = String(value || '').toLowerCase();
  if (v === 'high' || v === 'medium' || v === 'low') return v;
  return 'low';
}

function cleanBrand(value) {
  if (!value) return null;
  const s = String(value).trim();
  if (!s || /^(unknown|n\/a|none|null|unbranded|generic|not sure)$/i.test(s)) return null;
  return s;
}

function cleanText(value) {
  if (value == null) return null;
  const s = String(value).trim();
  if (!s || /^(unknown|n\/a|none|null|unbranded|generic|not sure)$/i.test(s)) return null;
  return s;
}

function normalizeCondition(value) {
  const v = String(value || '').toLowerCase().replace(/\s+/g, '-');
  if (['new', 'like-new', 'good', 'fair'].includes(v)) return v;
  if (v.includes('new') && (v.includes('tag') || v === 'brand-new')) return 'new';
  if (v.includes('like')) return 'like-new';
  if (v.includes('fair') || v.includes('poor') || v.includes('worn')) return 'fair';
  if (v.includes('good') || v.includes('gentle')) return 'good';
  return null;
}

function normalizePrice(value) {
  if (value == null || value === '') return null;
  const n = Number(value);
  if (!Number.isFinite(n) || n <= 0) return null;
  return Math.round(n * 100) / 100;
}

function normalizePriceRange(minValue, maxValue, midpoint) {
  let min = normalizePrice(minValue);
  let max = normalizePrice(maxValue);
  const mid = normalizePrice(midpoint);

  if (min != null && max != null && min > max) {
    [min, max] = [max, min];
  }

  if (min == null && max == null && mid != null) {
    min = Math.max(1, Math.round(mid * 0.75));
    max = Math.max(min, Math.round(mid * 1.25));
  }

  if (min != null && max == null) {
    max = Math.max(min, Math.round(min * 1.3));
  }
  if (max != null && min == null) {
    min = Math.max(1, Math.round(max * 0.7));
  }

  if (min != null && max != null && min === max) {
    min = Math.max(1, Math.round(min * 0.85));
    max = Math.round(max * 1.15);
  }

  return { min, max, mid: mid ?? (min != null && max != null ? Math.round(((min + max) / 2) * 100) / 100 : null) };
}

function normalizePayload(parsed, fallbackUrls) {
  const brand = cleanBrand(parsed.brand);
  const sourceUrls = Array.isArray(parsed.sourceUrls)
    ? parsed.sourceUrls.filter((u) => typeof u === 'string' && u.startsWith('http'))
    : [];

  const prices = normalizePriceRange(
    parsed.suggestedPriceMin,
    parsed.suggestedPriceMax,
    parsed.suggestedPrice
  );

  return {
    brand,
    color: cleanText(parsed.color),
    garmentType: cleanText(parsed.garmentType),
    title: cleanText(parsed.title) || cleanText(parsed.matchedProductName),
    size: cleanText(parsed.size),
    condition: normalizeCondition(parsed.condition),
    suggestedPrice: prices.mid,
    suggestedPriceMin: prices.min,
    suggestedPriceMax: prices.max,
    confidence: normalizeConfidence(parsed.confidence),
    matchedProductName: cleanText(parsed.matchedProductName),
    sourceUrls: sourceUrls.length ? [...new Set(sourceUrls)] : fallbackUrls,
    department: ['mens', 'womens', 'unisex'].includes(String(parsed.department || '').toLowerCase())
      ? String(parsed.department).toLowerCase()
      : null,
    warningCode: brand ? null : 'NO_BRAND',
  };
}

async function callClaude(images, toolType = WEB_SEARCH_TOOL_TYPE) {
  const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
  const imageBlocks = images.map((img) => ({
    type: 'image',
    source: {
      type: 'base64',
      media_type: img.mediaType,
      data: img.base64,
    },
  }));
  const count = images.length;
  try {
    return await client.messages.create({
      model: MODEL,
      max_tokens: 1024,
      tools: [
        {
          type: toolType,
          name: 'web_search',
          max_uses: 3,
        },
      ],
      system: SYSTEM_PROMPT,
      messages: [
        {
          role: 'user',
          content: [
            ...imageBlocks,
            {
              type: 'text',
              text:
                count > 1
                  ? `These ${count} photos are the same listing item. Use every photo to identify title, brand, color, garment type, size (if a tag is visible), and condition. Search the web if a logo, tag, or distinctive design needs confirmation.`
                  : 'Identify this item. Search the web if a logo, tag, or distinctive design needs confirmation.',
            },
          ],
        },
      ],
    });
  } catch (err) {
    const msg = String(err?.message || err);
    if (toolType !== 'web_search_20250305' && /web_search/i.test(msg)) {
      return callClaude(images, 'web_search_20250305');
    }
    throw err;
  }
}

router.post(
  '/',
  protectSupabase,
  identifyRateLimit,
  upload.array('images', 5),
  async (req, res) => {
    try {
      if (!process.env.ANTHROPIC_API_KEY) {
        return fail(
          res,
          503,
          'API_UNAVAILABLE',
          'Clothing scan is not configured on the server.'
        );
      }

      const images = extractImages(req).filter((img) => {
        const mediaType = String(img.mediaType || 'image/jpeg').toLowerCase();
        return ALLOWED_MEDIA.has(mediaType) && img.base64 && img.base64.length <= 7_000_000;
      }).map((img) => ({
        ...img,
        mediaType: String(img.mediaType || 'image/jpeg').toLowerCase(),
      }));

      if (!images.length) {
        return fail(res, 400, 'INVALID_IMAGE', 'Add 1–5 photos of the item to scan.');
      }

      let response;
      try {
        response = await callClaude(images);
      } catch (err) {
        const status = err?.status;
        if (status === 429) {
          return fail(res, 429, 'RATE_LIMITED', 'The identifier is busy. Try again in a moment.');
        }
        console.error('Anthropic identify error:', err?.message || err);
        return fail(
          res,
          503,
          'API_UNAVAILABLE',
          'Could not reach the identifier. Check your connection and try again.'
        );
      }

      const fallbackUrls = collectSourceUrls(response.content);
      const parsed = parseModelJson(lastTextBlock(response.content));
      if (!parsed) {
        return fail(res, 502, 'IDENTIFY_FAILED', 'Could not read a result from that photo. Try another angle.');
      }

      if (parsed.errorCode === 'NO_GARMENT') {
        return fail(
          res,
          422,
          'NO_GARMENT',
          'We couldn’t find a clothing item in that photo. Try a clearer shot of the piece.'
        );
      }
      if (parsed.errorCode === 'AMBIGUOUS') {
        return fail(
          res,
          422,
          'AMBIGUOUS',
          'We’re not sure what this is. Try a closer photo or enter the details yourself.'
        );
      }

      const payload = normalizePayload(parsed, fallbackUrls);
      if (!payload.garmentType && !payload.title && !payload.brand) {
        return fail(res, 422, 'AMBIGUOUS', 'We’re not sure what this is. Try another photo.');
      }

      return res.json(payload);
    } catch (err) {
      if (err instanceof multer.MulterError) {
        return fail(res, 400, 'INVALID_IMAGE', 'That photo is too large. Try a smaller image.');
      }
      console.error('identify-clothing error:', err);
      return fail(res, 502, 'IDENTIFY_FAILED', 'Something went wrong while scanning. Try again.');
    }
  }
);

module.exports = router;
