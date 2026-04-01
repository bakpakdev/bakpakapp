import React, { useState, useEffect, useContext, useRef } from 'react';
import {
  View,
  Text,
  FlatList,
  Image,
  TouchableOpacity,
  StyleSheet,
  RefreshControl,
  Dimensions,
  ScrollView,
  TextInput,
  Animated,
} from 'react-native';
import { useNavigation, useFocusEffect } from '@react-navigation/native';
import { api } from '../services/api';
import { Ionicons } from '@expo/vector-icons';
import { AuthContext } from '../context/AuthContext';
import { LinearGradient } from 'expo-linear-gradient';
import BakpakLogo from '../components/BakpakLogo';

const { width } = Dimensions.get('window');
const itemWidth = (width - 48) / 2; // 2 columns with padding

const CATEGORIES = ['Tops & Shirts', 'Bottoms', 'Shoes', 'Accessories', 'Jackets & Outerwear', 'Dresses & Skirts'];

export default function HomeScreen() {
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [cartCount, setCartCount] = useState(0);
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedCategory, setSelectedCategory] = useState(null);
  const [scrollY] = useState(new Animated.Value(0));
  const navigation = useNavigation();
  const { user } = useContext(AuthContext);
  const hasCreatedDemoRef = useRef(false);

  useFocusEffect(
    React.useCallback(() => {
      loadProducts();
      loadCartCount();
    }, [user?.id])
  );

  const loadCartCount = async () => {
    if (!user) return;
    try {
      const response = await api.get('/cart/count');
      setCartCount(response.data.count || 0);
    } catch (error) {
      console.error('Error loading cart count:', error);
    }
  };

  const createDemoListingIfNeeded = async () => {
    // Only create a demo listing once, and only if a user is logged in
    if (hasCreatedDemoRef.current || !user) return;

    try {
      console.log('No products found, creating demo listing for testing...');

      const formData = new FormData();
      formData.append('title', 'Demo Vintage Campus Hoodie');
      formData.append(
        'description',
        'This is a demo listing to help you test the app. You can safely ignore or delete it.'
      );
      formData.append('price', '35');
      formData.append('condition', 'Good');
      formData.append('size', 'L');
      formData.append('brand', 'Campus');
      formData.append('category', 'tops');
      formData.append('tags', JSON.stringify(['demo', 'test']));

      await api.post('/products', formData, {
        headers: {
          'Content-Type': 'multipart/form-data',
        },
      });

      hasCreatedDemoRef.current = true;
      // After creating the demo listing, reload products
      await loadProducts(true);
    } catch (error) {
      console.error('Error creating demo listing:', error);
    }
  };

  const loadProducts = async (skipDemo = false) => {
    try {
      const response = await api.get('/discover');
      let fetchedProducts = response.data || [];
      console.log('Discover feed loaded:', fetchedProducts.length, 'products');

      // If discover is empty, try fallback to /products
      if (fetchedProducts.length === 0) {
        const fallbackResponse = await api.get('/products');
        const fallbackProducts = fallbackResponse.data || [];
        console.log(
          'Fallback products loaded:',
          fallbackProducts.length,
          'products'
        );
        fetchedProducts = fallbackProducts;
      }

      setProducts(fetchedProducts);

      // If still no products and we haven't tried to create a demo yet, do it
      if (fetchedProducts.length === 0 && !skipDemo) {
        await createDemoListingIfNeeded();
      }
    } catch (error) {
      console.error('Error loading products for discover:', error);
      setProducts([]);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  };

  const onRefresh = () => {
    setRefreshing(true);
    loadProducts();
  };

  const handleScroll = Animated.event(
    [{ nativeEvent: { contentOffset: { y: scrollY } } }],
    { useNativeDriver: false }
  );

  const headerOpacity = scrollY.interpolate({
    inputRange: [0, 50],
    outputRange: [1, 0.95],
    extrapolate: 'clamp',
  });

  const renderProduct = ({ item, index }) => {
    const primaryImage = item.images?.find((img) => img.isPrimary) || item.images?.[0];

    return (
      <TouchableOpacity
        style={[styles.productCard, { marginLeft: index % 2 === 0 ? 0 : 8 }]}
        onPress={() => navigation.navigate('ProductDetail', { productId: item.id })}
        activeOpacity={0.8}
      >
        <View style={styles.productImageContainer}>
          <Image
            source={{ uri: primaryImage?.url || 'https://via.placeholder.com/200x200' }}
            style={styles.productImage}
          />
          <TouchableOpacity
            style={styles.heartButton}
            onPress={(e) => {
              e.stopPropagation();
              // Handle like functionality
            }}
          >
            <Ionicons name="heart-outline" size={16} color="#374151" />
          </TouchableOpacity>
          {item.condition && (
            <View style={styles.conditionBadge}>
              <Text style={styles.conditionText}>{item.condition}</Text>
            </View>
          )}
        </View>
        <View style={styles.productInfo}>
          <Text style={styles.productTitle} numberOfLines={1}>
            {item.title}
          </Text>
          <View style={styles.sellerInfo}>
            <Ionicons name="school-outline" size={12} color="#2563eb" />
            <Text style={styles.sellerName} numberOfLines={1}>
              {item.user?.username || 'seller'}
            </Text>
            {item.user?.verified && (
              <Ionicons name="checkmark-circle" size={12} color="#2563eb" />
            )}
          </View>
          <View style={styles.productFooter}>
            <Text style={styles.productPrice}>${item.price}</Text>
            {item._count?.likes > 0 && (
              <Text style={styles.likesCount}>{item._count.likes} saves</Text>
            )}
          </View>
        </View>
      </TouchableOpacity>
    );
  };

  if (loading) {
    return (
      <View style={styles.centerContainer}>
        <Text>Loading...</Text>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      {/* Header */}
      <Animated.View style={[styles.header, { opacity: headerOpacity }]}>
        <View style={styles.headerContent}>
          <View style={styles.headerLeft}>
            <Image 
              source={require('../../assets/logo.png')} 
              style={styles.headerLogo}
              resizeMode="contain"
            />
            <Text style={styles.headerTitle}>bakpak</Text>
          </View>
          <TouchableOpacity
            style={styles.cartButton}
            onPress={() => navigation.navigate('Cart')}
          >
            <Ionicons name="basket-outline" size={24} color="#000" />
            {cartCount > 0 && (
              <View style={styles.cartBadge}>
                <Text style={styles.cartBadgeText}>{cartCount > 99 ? '99+' : cartCount}</Text>
              </View>
            )}
          </TouchableOpacity>
        </View>
      </Animated.View>

      <ScrollView
        style={styles.scrollView}
        onScroll={handleScroll}
        scrollEventThrottle={16}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
        showsVerticalScrollIndicator={false}
      >
        {/* Featured Banner */}
        <View style={styles.bannerContainer}>
          <LinearGradient
            colors={['#154733', '#0f3528']}
            style={styles.banner}
          >
            <Image
              source={{ uri: 'https://images.unsplash.com/photo-1523050854058-8df90110c9f1?w=1200&auto=format&fit=crop&q=80' }}
              style={styles.bannerImage}
            />
            <View style={styles.bannerContent}>
              <View style={styles.bannerHeader}>
                <BakpakLogo size={32} color="#fff" />
                <Text style={styles.bannerTag}>Campus Marketplace</Text>
              </View>
              <Text style={styles.bannerTitle}>Buy & Sell on Campus</Text>
              <Text style={styles.bannerSubtitle}>
                From textbooks to dorm furniture - find everything you need from fellow students.
              </Text>
              <TouchableOpacity style={styles.bannerButton}>
                <Text style={styles.bannerButtonText}>Start Shopping</Text>
              </TouchableOpacity>
            </View>
          </LinearGradient>
        </View>

        {/* University Filter */}
        <View style={styles.universitySection}>
          <Text style={styles.universityLabel}>Shopping at:</Text>
          <TouchableOpacity style={styles.universityButton}>
            <Ionicons name="school-outline" size={16} color="#154733" />
            <Text style={styles.universityText}>UO Campus</Text>
            <Ionicons name="chevron-forward" size={16} color="#154733" />
          </TouchableOpacity>
        </View>

        {/* Categories */}
        <View style={styles.categoriesSection}>
          <View style={styles.sectionHeader}>
            <Text style={styles.sectionTitle}>Shop by Category</Text>
            <TouchableOpacity>
              <Text style={styles.seeAllText}>See all</Text>
            </TouchableOpacity>
          </View>
          <ScrollView
            horizontal
            showsHorizontalScrollIndicator={false}
            contentContainerStyle={styles.categoriesScroll}
          >
            {CATEGORIES.map((cat) => (
              <TouchableOpacity
                key={cat}
                style={[
                  styles.categoryButton,
                  selectedCategory === cat && styles.categoryButtonActive,
                ]}
                onPress={() => setSelectedCategory(cat === selectedCategory ? null : cat)}
              >
                <Text
                  style={[
                    styles.categoryText,
                    selectedCategory === cat && styles.categoryTextActive,
                  ]}
                >
                  {cat}
                </Text>
              </TouchableOpacity>
            ))}
          </ScrollView>
        </View>

        {/* Products Grid */}
        <View style={styles.productsSection}>
          <View style={styles.sectionHeader}>
            <Text style={styles.sectionTitle}>Available Near You</Text>
            <TouchableOpacity style={styles.filterButton}>
              <Ionicons name="filter-outline" size={20} color="#000" />
            </TouchableOpacity>
          </View>
          {products.length === 0 ? (
            <View style={styles.emptyContainer}>
              <Text style={styles.emptyText}>No products found</Text>
              <Text style={styles.emptySubtext}>Pull down to refresh</Text>
            </View>
          ) : (
            <FlatList
              data={products}
              renderItem={renderProduct}
              keyExtractor={(item) => item.id}
              numColumns={2}
              scrollEnabled={false}
              contentContainerStyle={styles.productsGrid}
            />
          )}
        </View>
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
  },
  header: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    zIndex: 100,
    backgroundColor: 'rgba(255, 255, 255, 0.95)',
    borderBottomWidth: 1,
    borderBottomColor: '#e5e7eb',
    paddingTop: 50,
    paddingBottom: 12,
  },
  headerContent: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
  },
  headerLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  headerLogo: {
    width: 44,
    height: 44,
  },
  headerTitle: {
    fontSize: 24,
    fontWeight: 'bold',
    color: '#111827',
    marginLeft: -4,
    marginTop: -2,
  },
  cartButton: {
    padding: 4,
    position: 'relative',
  },
  cartBadge: {
    position: 'absolute',
    top: 0,
    right: 0,
    backgroundColor: '#2563eb',
    borderRadius: 10,
    minWidth: 20,
    height: 20,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 6,
  },
  cartBadgeText: {
    color: '#fff',
    fontSize: 10,
    fontWeight: 'bold',
  },
  scrollView: {
    flex: 1,
    marginTop: 80,
  },
  bannerContainer: {
    paddingHorizontal: 16,
    marginBottom: 24,
  },
  banner: {
    height: 200,
    borderRadius: 16,
    overflow: 'hidden',
    position: 'relative',
  },
  bannerImage: {
    position: 'absolute',
    width: '100%',
    height: '100%',
    opacity: 0.3,
  },
  bannerContent: {
    flex: 1,
    padding: 24,
    justifyContent: 'center',
  },
  bannerHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginBottom: 12,
  },
  bannerTag: {
    color: 'rgba(255, 255, 255, 0.9)',
    fontSize: 14,
    fontWeight: '600',
  },
  bannerTitle: {
    fontSize: 28,
    fontWeight: 'bold',
    color: '#fff',
    marginBottom: 8,
  },
  bannerSubtitle: {
    fontSize: 14,
    color: 'rgba(255, 255, 255, 0.9)',
    marginBottom: 16,
  },
  bannerButton: {
    backgroundColor: '#fff',
    paddingVertical: 10,
    paddingHorizontal: 24,
    borderRadius: 8,
    alignSelf: 'flex-start',
  },
  bannerButtonText: {
    color: '#154733',
    fontSize: 14,
    fontWeight: 'bold',
  },
  universitySection: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingHorizontal: 16,
    marginBottom: 24,
  },
  universityLabel: {
    fontSize: 14,
    color: '#6b7280',
    fontWeight: '500',
  },
  universityButton: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    backgroundColor: '#e6f2ed',
    paddingVertical: 8,
    paddingHorizontal: 16,
    borderRadius: 20,
  },
  universityText: {
    fontSize: 14,
    fontWeight: 'bold',
    color: '#154733',
  },
  categoriesSection: {
    marginBottom: 32,
  },
  sectionHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 16,
    marginBottom: 12,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: 'bold',
    color: '#111827',
  },
  seeAllText: {
    fontSize: 14,
    fontWeight: '600',
    color: '#154733',
  },
  categoriesScroll: {
    paddingHorizontal: 16,
    gap: 12,
  },
  categoryButton: {
    paddingVertical: 10,
    paddingHorizontal: 20,
    backgroundColor: '#f3f4f6',
    borderRadius: 8,
    borderWidth: 1,
    borderColor: 'transparent',
  },
  categoryButtonActive: {
    backgroundColor: '#154733',
  },
  categoryText: {
    fontSize: 14,
    fontWeight: '600',
    color: '#374151',
  },
  categoryTextActive: {
    color: '#fff',
  },
  productsSection: {
    marginBottom: 100,
  },
  filterButton: {
    padding: 4,
  },
  productsGrid: {
    paddingHorizontal: 16,
  },
  productCard: {
    width: itemWidth,
    marginBottom: 24,
  },
  productImageContainer: {
    position: 'relative',
    width: '100%',
    aspectRatio: 3 / 4,
    borderRadius: 12,
    overflow: 'hidden',
    backgroundColor: '#f3f4f6',
    marginBottom: 8,
  },
  productImage: {
    width: '100%',
    height: '100%',
  },
  heartButton: {
    position: 'absolute',
    top: 8,
    right: 8,
    backgroundColor: 'rgba(255, 255, 255, 0.8)',
    padding: 6,
    borderRadius: 20,
  },
  conditionBadge: {
    position: 'absolute',
    bottom: 8,
    left: 8,
    backgroundColor: 'rgba(255, 255, 255, 0.9)',
    paddingVertical: 4,
    paddingHorizontal: 8,
    borderRadius: 4,
  },
  conditionText: {
    fontSize: 10,
    fontWeight: 'bold',
    textTransform: 'uppercase',
    color: '#111827',
  },
  productInfo: {
    gap: 4,
  },
  productTitle: {
    fontSize: 14,
    fontWeight: '600',
    color: '#111827',
  },
  sellerInfo: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  sellerName: {
    fontSize: 12,
    color: '#6b7280',
  },
  productFooter: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginTop: 4,
  },
  productPrice: {
    fontSize: 16,
    fontWeight: 'bold',
    color: '#2563eb',
  },
  likesCount: {
    fontSize: 12,
    color: '#9ca3af',
  },
  centerContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  emptyContainer: {
    padding: 40,
    alignItems: 'center',
  },
  emptyText: {
    fontSize: 18,
    fontWeight: '600',
    color: '#333',
    marginBottom: 8,
  },
  emptySubtext: {
    fontSize: 14,
    color: '#666',
  },
});
