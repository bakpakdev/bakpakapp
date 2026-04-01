import React, { useState, useEffect, useContext, useMemo, useRef } from 'react';
import {
  View,
  Text,
  TextInput,
  FlatList,
  Image,
  TouchableOpacity,
  StyleSheet,
  ScrollView,
  Animated,
  Platform,
  Dimensions,
} from 'react-native';
import { useNavigation, useFocusEffect } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { api } from '../services/api';
import { AuthContext } from '../context/AuthContext';

const { width } = Dimensions.get('window');
const CARD_WIDTH = (width - 48) / 2; // 2 columns with padding

const CATEGORIES = [
  { id: 'all', name: 'All', icon: 'grid-outline' },
  { id: 'tops', name: 'Tops & Shirts', icon: 'shirt-outline' },
  { id: 'bottoms', name: 'Bottoms', icon: 'body-outline' },
  { id: 'shoes', name: 'Shoes', icon: 'walk-outline' },
  { id: 'accessories', name: 'Accessories', icon: 'pricetags-outline' },
  { id: 'jackets', name: 'Jackets', icon: 'shirt-outline' },
  { id: 'dresses', name: 'Dresses', icon: 'shirt-outline' },
];

const TRENDING_SEARCHES = ['Vintage Tees', 'Thrifted Jeans', 'Game Day Fits', 'Campus Style'];

const RECENT_SEARCHES_KEY = '@recent_searches';
const MAX_RECENT_SEARCHES = 4;

export default function SearchScreen() {
  const [query, setQuery] = useState('');
  const [isFocused, setIsFocused] = useState(false);
  const [selectedCategory, setSelectedCategory] = useState('all');
  const [activeTab, setActiveTab] = useState('items');
  const [products, setProducts] = useState([]);
  const [categories, setCategories] = useState([]);
  const [cartCount, setCartCount] = useState(0);
  const [recentSearches, setRecentSearches] = useState([]);
  const [likedProducts, setLikedProducts] = useState(new Set());
  const [loading, setLoading] = useState(false);
  
  const navigation = useNavigation();
  const { user } = useContext(AuthContext);
  
  const suggestionsOpacity = useRef(new Animated.Value(0)).current;
  const resultsOpacity = useRef(new Animated.Value(1)).current;
  const tabUnderlineAnim = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    loadCategories();
    loadRecentSearches();
  }, []);

  useEffect(() => {
    if (isFocused && !query) {
      Animated.parallel([
        Animated.timing(suggestionsOpacity, {
          toValue: 1,
          duration: 200,
          useNativeDriver: Platform.OS !== 'web',
        }),
        Animated.timing(resultsOpacity, {
          toValue: 0,
          duration: 200,
          useNativeDriver: Platform.OS !== 'web',
        }),
      ]).start();
    } else {
      Animated.parallel([
        Animated.timing(suggestionsOpacity, {
          toValue: 0,
          duration: 200,
          useNativeDriver: Platform.OS !== 'web',
        }),
        Animated.timing(resultsOpacity, {
          toValue: 1,
          duration: 200,
          useNativeDriver: Platform.OS !== 'web',
        }),
      ]).start();
    }
  }, [isFocused, query]);

  useEffect(() => {
    Animated.timing(tabUnderlineAnim, {
      toValue: activeTab === 'items' ? 0 : 1,
      duration: 200,
      useNativeDriver: Platform.OS !== 'web',
    }).start();
  }, [activeTab]);

  useEffect(() => {
    performSearch();
  }, [query, selectedCategory]);

  useFocusEffect(
    React.useCallback(() => {
      loadCartCount();
      if (user) {
        loadLikedProducts();
      }
    }, [user?.id])
  );

  const loadRecentSearches = async () => {
    try {
      const stored = await AsyncStorage.getItem(RECENT_SEARCHES_KEY);
      if (stored) {
        setRecentSearches(JSON.parse(stored));
      }
    } catch (error) {
      console.error('Error loading recent searches:', error);
    }
  };

  const saveRecentSearch = async (searchText) => {
    if (!searchText.trim()) return;
    try {
      const updated = [searchText, ...recentSearches.filter(s => s !== searchText)].slice(0, MAX_RECENT_SEARCHES);
      setRecentSearches(updated);
      await AsyncStorage.setItem(RECENT_SEARCHES_KEY, JSON.stringify(updated));
    } catch (error) {
      console.error('Error saving recent search:', error);
    }
  };

  const loadCategories = async () => {
    try {
      const response = await api.get('/search/categories');
      setCategories(response.data);
    } catch (error) {
      console.error('Error loading categories:', error);
    }
  };

  const loadCartCount = async () => {
    if (!user) return;
    try {
      const response = await api.get('/cart/count');
      setCartCount(response.data.count || 0);
    } catch (error) {
      console.error('Error loading cart count:', error);
    }
  };

  const loadLikedProducts = async () => {
    if (!user) return;
    try {
      const response = await api.get('/social/liked');
      const likedIds = new Set(response.data.map(item => item.id));
      setLikedProducts(likedIds);
    } catch (error) {
      console.error('Error loading liked products:', error);
    }
  };

  const performSearch = async () => {
    setLoading(true);
    try {
      const params = {
        q: query || undefined,
        category: selectedCategory !== 'all' ? selectedCategory : undefined,
      };
      const response = await api.get('/search', { params });
      setProducts(response.data || []);
    } catch (error) {
      console.error('Search error:', error);
      setProducts([]);
    } finally {
      setLoading(false);
    }
  };

  const handleSearchSubmit = (text) => {
    setQuery(text);
    setIsFocused(false);
    saveRecentSearch(text);
  };

  const toggleLike = async (productId) => {
    if (!user) {
      navigation.navigate('Login');
      return;
    }

    const isLiked = likedProducts.has(productId);
    try {
      if (isLiked) {
        await api.delete(`/social/like/${productId}`);
        setLikedProducts(prev => {
          const newSet = new Set(prev);
          newSet.delete(productId);
          return newSet;
        });
      } else {
        await api.post(`/social/like/${productId}`);
        setLikedProducts(prev => new Set([...prev, productId]));
      }
    } catch (error) {
      console.error('Error toggling like:', error);
    }
  };

  const filteredProducts = useMemo(() => {
    return products.filter(item => {
      const matchesQuery = !query || 
        item.title?.toLowerCase().includes(query.toLowerCase()) ||
        item.user?.username?.toLowerCase().includes(query.toLowerCase());
      const matchesCategory = selectedCategory === 'all' || item.category === selectedCategory;
      return matchesQuery && matchesCategory;
    });
  }, [products, query, selectedCategory]);

  const renderProduct = ({ item }) => {
    const primaryImage = item.images?.find((img) => img.isPrimary) || item.images?.[0];
    const isLiked = likedProducts.has(item.id);
    const universityName = item.user?.username || 'Unknown';

    return (
      <TouchableOpacity
        style={styles.productCard}
        onPress={() => navigation.navigate('ProductDetail', { productId: item.id })}
        activeOpacity={0.9}
      >
        <View style={styles.productImageContainer}>
          <Image
            source={{ uri: primaryImage?.url || 'https://via.placeholder.com/400x500' }}
            style={styles.productImage}
            resizeMode="cover"
          />
          <TouchableOpacity
            style={styles.heartButton}
            onPress={(e) => {
              e.stopPropagation();
              toggleLike(item.id);
            }}
          >
            <Ionicons
              name={isLiked ? 'heart' : 'heart-outline'}
              size={16}
              color={isLiked ? '#154733' : '#666'}
            />
          </TouchableOpacity>
          <View style={styles.universityBadge}>
            <Ionicons name="school-outline" size={10} color="#000" />
            <Text style={styles.universityBadgeText}>
              {universityName.split(' ')[0]}
            </Text>
          </View>
        </View>
        <View style={styles.productInfo}>
          <Text style={styles.productTitle} numberOfLines={1}>
            {item.title}
          </Text>
          <View style={styles.productFooter}>
            <Text style={styles.productPrice}>${item.price}</Text>
            <Text style={styles.productSeller}>@{item.user?.username || 'unknown'}</Text>
          </View>
        </View>
      </TouchableOpacity>
    );
  };

  const renderSearchSuggestion = ({ item, icon, onPress }) => (
    <TouchableOpacity
      style={styles.suggestionItem}
      onPress={onPress}
      activeOpacity={0.7}
    >
      <Ionicons name={icon} size={16} color="#9ca3af" style={styles.suggestionIcon} />
      <Text style={styles.suggestionText}>{item}</Text>
      <Ionicons name="chevron-forward" size={16} color="#d1d5db" />
    </TouchableOpacity>
  );

  const tabUnderlineLeft = tabUnderlineAnim.interpolate({
    inputRange: [0, 1],
    outputRange: ['0%', '50%'],
  });

  return (
    <View style={styles.container}>
      {/* Sticky Header */}
      <View style={styles.header}>
        <View style={styles.searchBarContainer}>
          {isFocused && (
            <TouchableOpacity
              onPress={() => setIsFocused(false)}
              style={styles.backButton}
            >
              <Ionicons name="arrow-back" size={20} color="#4b5563" />
            </TouchableOpacity>
          )}
          <View style={[styles.searchInputContainer, isFocused && styles.searchInputContainerFocused]}>
            <Ionicons
              name="search"
              size={16}
              color={isFocused ? '#000' : '#9ca3af'}
              style={styles.searchIcon}
            />
            <TextInput
              style={styles.searchInput}
              placeholder="Search clothing, thrift finds, or sellers..."
              placeholderTextColor="#9ca3af"
              value={query}
              onChangeText={setQuery}
              onFocus={() => setIsFocused(true)}
              onSubmitEditing={() => {
                if (query.trim()) {
                  handleSearchSubmit(query);
                }
              }}
              returnKeyType="search"
            />
            {query ? (
              <TouchableOpacity onPress={() => setQuery('')} style={styles.clearButton}>
                <Ionicons name="close-circle" size={18} color="#6b7280" />
              </TouchableOpacity>
            ) : null}
          </View>
          {!isFocused && (
            <TouchableOpacity style={styles.filterButton}>
              <Ionicons name="options-outline" size={20} color="#374151" />
            </TouchableOpacity>
          )}
        </View>

        {/* Tab Selection */}
        {!isFocused && (
          <View style={styles.tabContainer}>
            <TouchableOpacity
              style={styles.tab}
              onPress={() => setActiveTab('items')}
            >
              <Text style={[styles.tabText, activeTab === 'items' && styles.tabTextActive]}>
                Items
              </Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={styles.tab}
              onPress={() => setActiveTab('shops')}
            >
              <Text style={[styles.tabText, activeTab === 'shops' && styles.tabTextActive]}>
                Shops
              </Text>
            </TouchableOpacity>
            <Animated.View
              style={[
                styles.tabUnderline,
                { left: tabUnderlineLeft },
              ]}
            />
          </View>
        )}
      </View>

      {/* Content */}
      <View style={styles.content}>
        {isFocused && !query ? (
          <Animated.View
            style={[
              styles.suggestionsContainer,
              { opacity: suggestionsOpacity },
            ]}
          >
            <ScrollView showsVerticalScrollIndicator={false}>
              {recentSearches.length > 0 && (
                <View style={styles.suggestionsSection}>
                  <View style={styles.sectionHeader}>
                    <Ionicons name="time-outline" size={12} color="#9ca3af" />
                    <Text style={styles.sectionHeaderText}>Recent Searches</Text>
                  </View>
                  <View style={styles.suggestionsBox}>
                    {recentSearches.map((item, index) => (
                      <View key={index}>
                        {renderSearchSuggestion({
                          item,
                          icon: 'time-outline',
                          onPress: () => handleSearchSubmit(item),
                        })}
                      </View>
                    ))}
                  </View>
                </View>
              )}

              <View style={styles.suggestionsSection}>
                <View style={styles.sectionHeader}>
                  <Ionicons name="trending-up-outline" size={12} color="#9ca3af" />
                  <Text style={styles.sectionHeaderText}>Popular on Campus</Text>
                </View>
                <View style={styles.suggestionsBox}>
                  {TRENDING_SEARCHES.map((item, index) => (
                    <View key={index}>
                      {renderSearchSuggestion({
                        item,
                        icon: 'trending-up-outline',
                        onPress: () => handleSearchSubmit(item),
                      })}
                    </View>
                  ))}
                </View>
              </View>
            </ScrollView>
          </Animated.View>
        ) : (
          <Animated.View
            style={[
              styles.resultsContainer,
              { opacity: resultsOpacity },
            ]}
          >
            <ScrollView
              showsVerticalScrollIndicator={false}
              contentContainerStyle={styles.resultsContent}
            >
              {/* Category Bubbles */}
              <ScrollView
                horizontal
                showsHorizontalScrollIndicator={false}
                contentContainerStyle={styles.categoriesContainer}
                style={styles.categoriesScroll}
              >
                {CATEGORIES.map((cat) => {
                  const isActive = selectedCategory === cat.id;
                  return (
                    <TouchableOpacity
                      key={cat.id}
                      style={[
                        styles.categoryChip,
                        isActive && styles.categoryChipActive,
                      ]}
                      onPress={() => setSelectedCategory(cat.id)}
                    >
                      {cat.id === 'all' && (
                        <Ionicons
                          name={cat.icon}
                          size={14}
                          color={isActive ? '#fff' : '#4b5563'}
                        />
                      )}
                      <Text
                        style={[
                          styles.categoryChipText,
                          isActive && styles.categoryChipTextActive,
                        ]}
                      >
                        {cat.name}
                      </Text>
                    </TouchableOpacity>
                  );
                })}
              </ScrollView>

              {/* Results Section */}
              <View style={styles.resultsSection}>
                <View style={styles.resultsHeader}>
                  <Text style={styles.resultsTitle}>
                    {query ? `Results for "${query}"` : 'Recently Listed'}
                  </Text>
                  <Text style={styles.resultsCount}>
                    {filteredProducts.length} items
                  </Text>
                </View>

                {loading ? (
                  <View style={styles.loadingContainer}>
                    <Text style={styles.loadingText}>Loading...</Text>
                  </View>
                ) : filteredProducts.length > 0 ? (
                  <View style={styles.productsGrid}>
                    {filteredProducts.map((item) => (
                      <View key={item.id} style={styles.productWrapper}>
                        {renderProduct({ item })}
                      </View>
                    ))}
                  </View>
                ) : (
                  <View style={styles.emptyContainer}>
                    <View style={styles.emptyIconContainer}>
                      <Ionicons name="search" size={32} color="#d1d5db" />
                    </View>
                    <Text style={styles.emptyTitle}>No items found</Text>
                    <Text style={styles.emptyText}>
                      Try adjusting your search or category filters.
                    </Text>
                    <TouchableOpacity
                      style={styles.clearFiltersButton}
                      onPress={() => {
                        setQuery('');
                        setSelectedCategory('all');
                      }}
                    >
                      <Text style={styles.clearFiltersText}>Clear all filters</Text>
                    </TouchableOpacity>
                  </View>
                )}
              </View>

              {/* Recommended Nearby Section */}
              {!query && filteredProducts.length > 0 && (
                <View style={styles.nearbySection}>
                  <View style={styles.nearbyHeader}>
                    <Ionicons name="location-outline" size={16} color="#000" />
                    <Text style={styles.nearbyTitle}>Available at your University</Text>
                  </View>
                  <View style={styles.productsGrid}>
                    {filteredProducts.slice(0, 2).map((item) => (
                      <View key={`nearby-${item.id}`} style={styles.productWrapper}>
                        {renderProduct({ item })}
                      </View>
                    ))}
                  </View>
                </View>
              )}
            </ScrollView>
          </Animated.View>
        )}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
  },
  header: {
    backgroundColor: '#fff',
    paddingTop: Platform.OS === 'ios' ? 50 : 40,
    paddingBottom: 8,
    paddingHorizontal: 16,
    borderBottomWidth: 1,
    borderBottomColor: '#f3f4f6',
  },
  searchBarContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  backButton: {
    padding: 4,
  },
  searchInputContainer: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#f3f4f6',
    borderRadius: 20,
    paddingHorizontal: 12,
    height: 40,
  },
  searchInputContainerFocused: {
    backgroundColor: '#fff',
    borderWidth: 2,
    borderColor: '#000',
  },
  searchIcon: {
    marginRight: 8,
  },
  searchInput: {
    flex: 1,
    fontSize: 14,
    color: '#000',
    paddingVertical: 0,
  },
  clearButton: {
    padding: 4,
  },
  filterButton: {
    padding: 8,
  },
  tabContainer: {
    flexDirection: 'row',
    marginTop: 16,
    position: 'relative',
    borderBottomWidth: 1,
    borderBottomColor: '#f3f4f6',
  },
  tab: {
    flex: 1,
    paddingBottom: 8,
    alignItems: 'center',
  },
  tabText: {
    fontSize: 14,
    fontWeight: '600',
    color: '#9ca3af',
  },
  tabTextActive: {
    color: '#000',
  },
  tabUnderline: {
    position: 'absolute',
    bottom: 0,
    width: '50%',
    height: 2,
    backgroundColor: '#154733',
  },
  content: {
    flex: 1,
  },
  suggestionsContainer: {
    flex: 1,
    paddingTop: 16,
  },
  suggestionsSection: {
    marginBottom: 32,
    paddingHorizontal: 16,
  },
  sectionHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginBottom: 12,
    paddingLeft: 8,
  },
  sectionHeaderText: {
    fontSize: 10,
    fontWeight: '700',
    textTransform: 'uppercase',
    letterSpacing: 1,
    color: '#9ca3af',
  },
  suggestionsBox: {
    backgroundColor: '#fff',
    borderRadius: 16,
    borderWidth: 1,
    borderColor: '#f3f4f6',
    overflow: 'hidden',
  },
  suggestionItem: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 16,
    borderBottomWidth: 1,
    borderBottomColor: '#f3f4f6',
  },
  suggestionIcon: {
    marginRight: 12,
  },
  suggestionText: {
    flex: 1,
    fontSize: 14,
    fontWeight: '500',
    color: '#374151',
  },
  resultsContainer: {
    flex: 1,
  },
  resultsContent: {
    paddingBottom: 20,
  },
  categoriesContainer: {
    paddingHorizontal: 16,
    paddingTop: 8,
    paddingBottom: 24,
    gap: 8,
  },
  categoriesScroll: {
    maxHeight: 50,
  },
  categoryChip: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 6,
    paddingHorizontal: 18,
    paddingTop: 12,
    paddingBottom: 12,
    borderRadius: 22,
    backgroundColor: '#f3f4f6',
    minHeight: 44,
    overflow: 'visible',
  },
  categoryChipActive: {
    backgroundColor: '#154733',
  },
  categoryChipText: {
    fontSize: 14,
    fontWeight: '600',
    color: '#4b5563',
  },
  categoryChipTextActive: {
    color: '#fff',
  },
  resultsSection: {
    paddingHorizontal: 16,
  },
  resultsHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 16,
  },
  resultsTitle: {
    fontSize: 18,
    fontWeight: '700',
    color: '#111827',
  },
  resultsCount: {
    fontSize: 12,
    fontWeight: '500',
    color: '#6b7280',
  },
  loadingContainer: {
    paddingVertical: 40,
    alignItems: 'center',
  },
  loadingText: {
    fontSize: 14,
    color: '#6b7280',
  },
  productsGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 16,
    marginBottom: 24,
  },
  productWrapper: {
    width: CARD_WIDTH,
  },
  productCard: {
    backgroundColor: '#fff',
    borderRadius: 12,
    overflow: 'hidden',
    borderWidth: 1,
    borderColor: '#f3f4f6',
    marginBottom: 16,
  },
  productImageContainer: {
    position: 'relative',
    width: '100%',
    aspectRatio: 4 / 5,
    backgroundColor: '#f3f4f6',
  },
  productImage: {
    width: '100%',
    height: '100%',
  },
  heartButton: {
    position: 'absolute',
    top: 8,
    right: 8,
    padding: 6,
    backgroundColor: 'rgba(255, 255, 255, 0.8)',
    borderRadius: 20,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.1,
    shadowRadius: 2,
    elevation: 2,
  },
  universityBadge: {
    position: 'absolute',
    bottom: 8,
    left: 8,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    paddingHorizontal: 8,
    paddingVertical: 4,
    backgroundColor: 'rgba(255, 255, 255, 0.9)',
    borderRadius: 6,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.1,
    shadowRadius: 2,
    elevation: 2,
  },
  universityBadgeText: {
    fontSize: 10,
    fontWeight: '700',
    textTransform: 'uppercase',
    letterSpacing: 0.5,
    color: '#000',
  },
  productInfo: {
    padding: 12,
  },
  productTitle: {
    fontSize: 14,
    fontWeight: '600',
    color: '#111827',
    marginBottom: 4,
  },
  productFooter: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  productPrice: {
    fontSize: 18,
    fontWeight: '700',
    color: '#111827',
  },
  productSeller: {
    fontSize: 11,
    color: '#9ca3af',
  },
  emptyContainer: {
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 80,
  },
  emptyIconContainer: {
    width: 64,
    height: 64,
    backgroundColor: '#f9fafb',
    borderRadius: 32,
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: 16,
  },
  emptyTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: '#111827',
    marginBottom: 4,
  },
  emptyText: {
    fontSize: 14,
    color: '#6b7280',
    textAlign: 'center',
    maxWidth: 200,
    marginBottom: 24,
  },
  clearFiltersButton: {
    paddingVertical: 8,
  },
  clearFiltersText: {
    fontSize: 14,
    fontWeight: '700',
    color: '#000',
    textDecorationLine: 'underline',
  },
  nearbySection: {
    marginTop: 32,
    paddingTop: 32,
    borderTopWidth: 1,
    borderTopColor: '#f3f4f6',
    paddingHorizontal: 16,
  },
  nearbyHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginBottom: 16,
  },
  nearbyTitle: {
    fontSize: 16,
    fontWeight: '700',
    color: '#111827',
  },
});
