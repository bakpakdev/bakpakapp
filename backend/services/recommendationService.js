const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

/**
 * Calculate listing quality score based on description, keywords, and hashtags
 * Similar to Depop's emphasis on well-crafted listings
 */
function calculateListingQualityScore(product) {
  let score = 0;
  
  // Description quality (0-40 points)
  const descriptionLength = product.description?.length || 0;
  if (descriptionLength > 200) score += 40;
  else if (descriptionLength > 100) score += 30;
  else if (descriptionLength > 50) score += 20;
  else if (descriptionLength > 20) score += 10;
  
  // Keywords in title and description (0-30 points)
  const titleWords = (product.title?.toLowerCase().split(/\s+/) || []).length;
  const descriptionWords = (product.description?.toLowerCase().split(/\s+/) || []).length;
  const totalWords = titleWords + descriptionWords;
  if (totalWords > 30) score += 30;
  else if (totalWords > 20) score += 20;
  else if (totalWords > 10) score += 10;
  
  // Hashtags/tags (0-20 points)
  const tags = Array.isArray(product.tags) ? product.tags : [];
  if (tags.length > 5) score += 20;
  else if (tags.length > 3) score += 15;
  else if (tags.length > 1) score += 10;
  else if (tags.length === 1) score += 5;
  
  // Brand information (0-10 points)
  if (product.brand) score += 10;
  
  return Math.min(score, 100); // Cap at 100
}

/**
 * Extract keywords from text (simple keyword extraction)
 */
function extractKeywords(text) {
  if (!text) return [];
  
  // Remove common stop words
  const stopWords = new Set(['the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for', 'of', 'with', 'by', 'is', 'are', 'was', 'were', 'be', 'been', 'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would', 'could', 'should', 'may', 'might', 'must', 'can']);
  
  const words = text.toLowerCase()
    .replace(/[^\w\s#]/g, ' ')
    .split(/\s+/)
    .filter(word => word.length > 2 && !stopWords.has(word));
  
  // Count frequency
  const wordFreq = {};
  words.forEach(word => {
    wordFreq[word] = (wordFreq[word] || 0) + 1;
  });
  
  // Return top keywords
  return Object.entries(wordFreq)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 10)
    .map(([word]) => word);
}

/**
 * Calculate relevance score for search query
 */
function calculateRelevanceScore(product, query) {
  if (!query) return 0;
  
  const queryLower = query.toLowerCase();
  const queryWords = queryLower.split(/\s+/);
  let score = 0;
  
  // Title match (highest weight)
  const titleLower = product.title?.toLowerCase() || '';
  queryWords.forEach(word => {
    if (titleLower.includes(word)) {
      score += 10;
      if (titleLower.startsWith(word)) score += 5; // Bonus for starting with keyword
    }
  });
  
  // Exact title match bonus
  if (titleLower.includes(queryLower)) score += 20;
  
  // Description match
  const descLower = product.description?.toLowerCase() || '';
  queryWords.forEach(word => {
    if (descLower.includes(word)) score += 3;
  });
  
  // Brand match
  if (product.brand?.toLowerCase().includes(queryLower)) score += 15;
  
  // Tag/hashtag match
  const tags = Array.isArray(product.tags) ? product.tags : [];
  tags.forEach(tag => {
    const tagLower = tag.toLowerCase();
    if (tagLower.includes(queryLower)) score += 8;
    queryWords.forEach(word => {
      if (tagLower.includes(word)) score += 5;
    });
  });
  
  // Category match
  if (product.category?.toLowerCase().includes(queryLower)) score += 5;
  
  return score;
}

/**
 * Get user preferences based on behavior history
 */
async function getUserPreferences(userId) {
  if (!userId) return null;
  
  // Get user's liked products
  const likedProducts = await prisma.like.findMany({
    where: { userId },
    include: {
      product: {
        select: {
          category: true,
          brand: true,
          tags: true,
          price: true,
        },
      },
    },
    take: 50,
  });
  
  // Get user's saved products
  const savedProducts = await prisma.savedItem.findMany({
    where: { userId },
    include: {
      product: {
        select: {
          category: true,
          brand: true,
          tags: true,
          price: true,
        },
      },
    },
    take: 50,
  });
  
  // Get user's viewed products
  const viewedProducts = await prisma.productView.findMany({
    where: { userId },
    include: {
      product: {
        select: {
          category: true,
          brand: true,
          tags: true,
          price: true,
        },
      },
    },
    take: 100,
    orderBy: { createdAt: 'desc' },
  });
  
  // Get user's purchased products
  const purchasedProducts = await prisma.order.findMany({
    where: { buyerId: userId },
    include: {
      items: {
        include: {
          product: {
            select: {
              category: true,
              brand: true,
              tags: true,
              price: true,
            },
          },
        },
      },
    },
  });
  
  // Analyze preferences
  const categoryFreq = {};
  const brandFreq = {};
  const tagFreq = {};
  const priceRange = { min: Infinity, max: 0, sum: 0, count: 0 };
  
  const allInteractions = [
    ...likedProducts.map(l => l.product),
    ...savedProducts.map(s => s.product),
    ...viewedProducts.map(v => v.product),
    ...purchasedProducts.flatMap(o => o.items.map(i => i.product)),
  ];
  
  allInteractions.forEach(product => {
    // Category frequency
    if (product.category) {
      categoryFreq[product.category] = (categoryFreq[product.category] || 0) + 1;
    }
    
    // Brand frequency
    if (product.brand) {
      brandFreq[product.brand] = (brandFreq[product.brand] || 0) + 1;
    }
    
    // Tag frequency
    if (Array.isArray(product.tags)) {
      product.tags.forEach(tag => {
        tagFreq[tag] = (tagFreq[tag] || 0) + 1;
      });
    }
    
    // Price range
    if (product.price) {
      priceRange.min = Math.min(priceRange.min, product.price);
      priceRange.max = Math.max(priceRange.max, product.price);
      priceRange.sum += product.price;
      priceRange.count += 1;
    }
  });
  
  // Get top preferences
  const topCategories = Object.entries(categoryFreq)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
    .map(([cat]) => cat);
  
  const topBrands = Object.entries(brandFreq)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
    .map(([brand]) => brand);
  
  const topTags = Object.entries(tagFreq)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 10)
    .map(([tag]) => tag);
  
  const avgPrice = priceRange.count > 0 ? priceRange.sum / priceRange.count : null;
  
  return {
    categories: topCategories,
    brands: topBrands,
    tags: topTags,
    priceRange: {
      min: priceRange.min === Infinity ? null : priceRange.min,
      max: priceRange.max === 0 ? null : priceRange.max,
      average: avgPrice,
    },
  };
}

/**
 * Calculate personalized recommendation score for a product
 */
function calculatePersonalizedScore(product, userPreferences) {
  if (!userPreferences) return 0;
  
  let score = 0;
  
  // Category match (0-30 points)
  if (userPreferences.categories.includes(product.category)) {
    score += 30;
  }
  
  // Brand match (0-25 points)
  if (product.brand && userPreferences.brands.includes(product.brand)) {
    score += 25;
  }
  
  // Tag match (0-20 points)
  const productTags = Array.isArray(product.tags) ? product.tags : [];
  const matchingTags = productTags.filter(tag => 
    userPreferences.tags.some(prefTag => 
      tag.toLowerCase().includes(prefTag.toLowerCase()) || 
      prefTag.toLowerCase().includes(tag.toLowerCase())
    )
  );
  score += Math.min(matchingTags.length * 5, 20);
  
  // Price preference (0-15 points)
  if (userPreferences.priceRange.average) {
    const priceDiff = Math.abs(product.price - userPreferences.priceRange.average);
    const priceRange = userPreferences.priceRange.max - userPreferences.priceRange.min || 100;
    const priceScore = Math.max(0, 15 - (priceDiff / priceRange) * 15);
    score += priceScore;
  }
  
  // Listing quality (0-10 points)
  const qualityScore = calculateListingQualityScore(product);
  score += qualityScore * 0.1;
  
  return score;
}

/**
 * Get personalized recommendations for a user
 */
async function getPersonalizedRecommendations(userId, limit = 20) {
  const userPreferences = await getUserPreferences(userId);
  
  // Get all available products
  const products = await prisma.product.findMany({
    where: {
      isSold: false,
      ...(userId && {
        userId: { not: userId }, // Don't recommend user's own products
      }),
    },
    include: {
      images: {
        where: { isPrimary: true },
      },
      user: {
        select: {
          id: true,
          username: true,
          avatar: true,
        },
      },
      _count: {
        select: {
          likes: true,
          views: true,
        },
      },
    },
    take: limit * 3, // Get more to filter and sort
  });
  
  // Calculate scores for each product
  const scoredProducts = products.map(product => {
    const personalizedScore = calculatePersonalizedScore(product, userPreferences);
    const qualityScore = calculateListingQualityScore(product);
    const engagementScore = (product._count.likes * 2) + (product._count.views * 0.1);
    
    // Combined score: 50% personalized, 30% quality, 20% engagement
    const totalScore = (personalizedScore * 0.5) + (qualityScore * 0.3) + (engagementScore * 0.2);
    
    return {
      ...product,
      recommendationScore: totalScore,
      personalizedScore,
      qualityScore,
      engagementScore,
    };
  });
  
  // Sort by score and return top results
  return scoredProducts
    .sort((a, b) => b.recommendationScore - a.recommendationScore)
    .slice(0, limit);
}

module.exports = {
  calculateListingQualityScore,
  calculateRelevanceScore,
  extractKeywords,
  getUserPreferences,
  calculatePersonalizedScore,
  getPersonalizedRecommendations,
};

