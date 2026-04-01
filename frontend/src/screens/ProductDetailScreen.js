import React, { useState, useEffect, useContext, useRef } from 'react';
import {
  View,
  Text,
  ScrollView,
  Image,
  TouchableOpacity,
  StyleSheet,
  Dimensions,
  Alert,
  FlatList,
  Modal,
  RefreshControl,
} from 'react-native';
import { useRoute, useNavigation } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import { api } from '../services/api';
import { AuthContext } from '../context/AuthContext';

const { width } = Dimensions.get('window');

export default function ProductDetailScreen() {
  const route = useRoute();
  const navigation = useNavigation();
  const { productId } = route.params || {};
  
  console.log('ProductDetailScreen mounted with productId:', productId);
  const { user } = useContext(AuthContext);
  const [product, setProduct] = useState(null);
  const [liked, setLiked] = useState(false);
  const [saved, setSaved] = useState(false);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [currentImageIndex, setCurrentImageIndex] = useState(0);
  const [showMenu, setShowMenu] = useState(false);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const imageListRef = useRef(null);

  useEffect(() => {
    loadProduct();
    checkLiked();
    checkSaved();
    setCurrentImageIndex(0);
  }, [productId]);

  useEffect(() => {
    if (product?.images) {
      setCurrentImageIndex(0);
    }
  }, [product?.id]);

  const loadProduct = async (isRefresh = false) => {
    try {
      if (isRefresh) {
        setRefreshing(true);
      }
      const response = await api.get(`/products/${productId}`);
      console.log('Product loaded:', response.data);
      console.log('Product images:', response.data.images);
      setProduct(response.data);
    } catch (error) {
      console.error('Error loading product:', error);
      if (error.response?.status === 404) {
        Alert.alert(
          'Product Not Found',
          'This listing may have been deleted or does not exist.',
          [
            {
              text: 'OK',
              onPress: () => navigation.goBack(),
            },
          ]
        );
      } else {
        if (!isRefresh) {
          Alert.alert('Error', error.response?.data?.message || 'Failed to load product');
        }
      }
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  };

  const onRefresh = () => {
    loadProduct(true);
  };

  const checkLiked = async () => {
    try {
      const response = await api.get(`/social/likes/${productId}`);
      setLiked(response.data.liked);
    } catch (error) {
      // Ignore
    }
  };

  const checkSaved = async () => {
    try {
      const savedItems = await api.get('/social/saved');
      setSaved(savedItems.data.some((item) => item.id === productId));
    } catch (error) {
      // Ignore
    }
  };

  const handleLike = async () => {
    try {
      if (liked) {
        await api.delete(`/social/like/${productId}`);
        setLiked(false);
      } else {
        await api.post(`/social/like/${productId}`);
        setLiked(true);
      }
    } catch (error) {
      Alert.alert('Error', 'Failed to like product');
    }
  };

  const handleSave = async () => {
    try {
      if (saved) {
        await api.delete(`/social/save/${productId}`);
        setSaved(false);
      } else {
        await api.post(`/social/save/${productId}`);
        setSaved(true);
      }
    } catch (error) {
      Alert.alert('Error', 'Failed to save product');
    }
  };

  const handleMessage = () => {
    if (product.user.id === user.id) {
      Alert.alert('Info', 'This is your own product');
      return;
    }
    // Go to the Messages tab and open a conversation with this seller
    navigation.navigate('MainTabs', {
      screen: 'Messages',
      params: { otherUserId: product.user.id },
    });
  };

  const handleBuy = () => {
    if (product.user.id === user.id) {
      Alert.alert('Info', 'Cannot buy your own product');
      return;
    }
    navigation.navigate('Checkout', { productId: product.id });
  };

  const handleAddToCart = async () => {
    if (!user) {
      Alert.alert('Login Required', 'Please login to add items to cart');
      return;
    }
    if (product.user.id === user.id) {
      Alert.alert('Info', 'Cannot add your own product to cart');
      return;
    }
    try {
      await api.post('/cart', { productId: product.id, quantity: 1 });
      Alert.alert('Success', 'Item added to cart');
    } catch (error) {
      Alert.alert('Error', error.response?.data?.message || 'Failed to add item to cart');
    }
  };

  const handleBack = () => {
    navigation.goBack();
  };

  const isOwner = product && user && product.user.id === user.id;

  const handleEdit = () => {
    setShowMenu(false);
    navigation.navigate('EditListing', { productId: product.id });
  };

  const handleDelete = () => {
    setShowMenu(false);
    setShowDeleteConfirm(true);
  };

  const confirmDelete = async () => {
    setShowDeleteConfirm(false);
    setDeleting(true);
    try {
      console.log('Deleting product:', productId);
      const response = await api.delete(`/products/${productId}`);
      console.log('Delete response:', response.data);
      setDeleting(false);
      // Navigate back - listing will disappear from all screens due to useFocusEffect
      navigation.goBack();
    } catch (error) {
      console.error('Delete error:', error);
      console.error('Delete error response:', error.response?.data);
      Alert.alert('Error', error.response?.data?.message || error.message || 'Failed to delete listing');
      setDeleting(false);
    }
  };

  const cancelDelete = () => {
    setShowDeleteConfirm(false);
  };

  const renderImage = ({ item }) => {
    const imageUrl = item.url;
    console.log('Rendering image:', imageUrl, 'Item:', item);
    
    if (!imageUrl) {
      console.warn('No image URL found for item:', item);
      return (
        <View style={[styles.imageContainer, styles.placeholderContainer]}>
          <Ionicons name="image-outline" size={64} color="#ccc" />
          <Text style={styles.placeholderText}>No Image</Text>
        </View>
      );
    }
    
    return (
      <View style={styles.imageContainer}>
        <Image
          source={{ uri: imageUrl }}
          style={styles.mainImage}
          resizeMode="contain"
          onError={(error) => {
            console.error('Image load error:', error.nativeEvent.error);
            console.error('Failed to load image URL:', imageUrl);
            console.error('Image item:', item);
          }}
        />
      </View>
    );
  };

  const onImageScroll = (event) => {
    const contentOffsetX = event.nativeEvent.contentOffset.x;
    const slideSize = event.nativeEvent.layoutMeasurement.width;
    const index = Math.round(contentOffsetX / slideSize);
    const maxIndex = (product?.images?.length || 1) - 1;
    const newIndex = Math.max(0, Math.min(index, maxIndex));
    if (newIndex !== currentImageIndex) {
      setCurrentImageIndex(newIndex);
    }
  };

  if (loading || !product) {
    return (
      <View style={styles.centerContainer}>
        <Text>Loading...</Text>
      </View>
    );
  }

  const images = product.images || [];
  console.log('Images array:', images);
  const sortedImages = [...images].sort((a, b) => {
    if (a.isPrimary) return -1;
    if (b.isPrimary) return 1;
    return 0;
  });
  console.log('Sorted images:', sortedImages);

  const views = product.views || product._count?.views || 0;
  const likesCount = product._count?.likes || 0;
  const postedAt = product.createdAt
    ? new Date(product.createdAt).toLocaleDateString()
    : '';

  return (
    <View style={styles.container}>
      <TouchableOpacity style={styles.backButton} onPress={handleBack}>
        <Ionicons name="arrow-back" size={24} color="#000" />
      </TouchableOpacity>
      
      {isOwner && (
        <TouchableOpacity style={styles.menuButton} onPress={() => setShowMenu(true)}>
          <Ionicons name="ellipsis-vertical" size={24} color="#000" />
        </TouchableOpacity>
      )}
      
      <Modal
        visible={showMenu}
        transparent={true}
        animationType="fade"
        onRequestClose={() => setShowMenu(false)}
      >
        <TouchableOpacity
          style={styles.modalOverlay}
          activeOpacity={1}
          onPress={() => setShowMenu(false)}
        >
          <View style={styles.menuContainer} onStartShouldSetResponder={() => true}>
            <TouchableOpacity style={styles.menuItem} onPress={handleEdit}>
              <Ionicons name="create-outline" size={20} color="#000" />
              <Text style={styles.menuItemText}>Edit Listing</Text>
            </TouchableOpacity>
            <TouchableOpacity style={[styles.menuItem, styles.deleteMenuItem]} onPress={handleDelete}>
              <Ionicons name="trash-outline" size={20} color="#ff4444" />
              <Text style={[styles.menuItemText, styles.deleteText]}>Delete Listing</Text>
            </TouchableOpacity>
          </View>
        </TouchableOpacity>
      </Modal>

      <Modal
        visible={showDeleteConfirm}
        transparent={true}
        animationType="fade"
        onRequestClose={cancelDelete}
      >
        <View style={styles.modalOverlay}>
          <View style={styles.confirmModalContainer}>
            <Text style={styles.confirmModalTitle}>Delete Listing</Text>
            <Text style={styles.confirmModalMessage}>
              Are you sure you want to delete this listing? This action cannot be undone.
            </Text>
            <View style={styles.confirmModalButtons}>
              <TouchableOpacity style={styles.confirmCancelButton} onPress={cancelDelete}>
                <Text style={styles.confirmCancelText}>Cancel</Text>
              </TouchableOpacity>
              <TouchableOpacity 
                style={[styles.confirmDeleteButton, deleting && styles.buttonDisabled]} 
                onPress={confirmDelete}
                disabled={deleting}
              >
                <Text style={styles.confirmDeleteText}>
                  {deleting ? 'Deleting...' : 'Delete'}
                </Text>
              </TouchableOpacity>
            </View>
          </View>
        </View>
      </Modal>
      
      <ScrollView 
        style={styles.scrollContent}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={onRefresh}
            tintColor="#000"
            colors={['#000']}
          />
        }
        nestedScrollEnabled={true}
      >
        {sortedImages.length > 0 ? (
          <>
            <FlatList
              ref={imageListRef}
              data={sortedImages}
              renderItem={renderImage}
              keyExtractor={(item, index) => item.id || `image-${index}`}
              horizontal
              pagingEnabled
              showsHorizontalScrollIndicator={false}
              onScroll={onImageScroll}
              scrollEventThrottle={16}
              nestedScrollEnabled={true}
              style={styles.imageCarousel}
            />
            {sortedImages.length > 1 && (
              <View style={styles.imageIndicators}>
                {sortedImages.map((_, index) => (
                  <View
                    key={index}
                    style={[
                      styles.indicator,
                      index === currentImageIndex && styles.activeIndicator,
                    ]}
                  />
                ))}
              </View>
            )}
          </>
        ) : (
          <View style={[styles.imageContainer, styles.placeholderContainer]}>
            <Ionicons name="image-outline" size={64} color="#ccc" />
            <Text style={styles.placeholderText}>No Images</Text>
          </View>
        )}
        <View style={styles.content}>
          {/* Price & Title */}
          <View style={styles.priceTitleSection}>
            <Text style={styles.price}>
              ${Number(product.price || 0).toFixed(2)}
            </Text>
            {product.originalPrice && (
              <View style={styles.originalPriceRow}>
                <Text style={styles.originalPrice}>
                  ${Number(product.originalPrice).toFixed(2)}
                </Text>
                <Text style={styles.discountText}>
                  {Math.round(
                    ((Number(product.originalPrice) - Number(product.price || 0)) /
                      Number(product.originalPrice)) *
                      100
                  )}
                  % off
                </Text>
              </View>
            )}
            <Text style={styles.title}>{product.title}</Text>
          </View>

          {/* Stats Bar */}
          <View style={styles.statsRow}>
            <View style={styles.statsItem}>
              <Ionicons name="eye-outline" size={14} color="#6b7280" />
              <Text style={styles.statsText}>{views} views</Text>
            </View>
            <View style={styles.statsDot} />
            <View style={styles.statsItem}>
              <Ionicons name="heart-outline" size={14} color="#6b7280" />
              <Text style={styles.statsText}>{likesCount} saves</Text>
            </View>
            <View style={styles.statsDot} />
            <View style={styles.statsItem}>
              <Ionicons name="time-outline" size={14} color="#6b7280" />
              <Text style={styles.statsText}>{postedAt}</Text>
            </View>
          </View>

          {/* Seller Card */}
          <TouchableOpacity
            style={styles.sellerCard}
            onPress={() =>
              navigation.navigate('UserProfile', { userId: product.user.id })
            }
          >
            <View style={styles.sellerTopRow}>
              <Image
                source={{
                  uri: product.user.avatar || 'https://via.placeholder.com/56',
                }}
                style={styles.sellerAvatarLarge}
              />
              <View style={styles.sellerInfoContainer}>
                <View style={styles.sellerNameRow}>
                  <Text style={styles.sellerName}>{product.user.username}</Text>
                  {product.user.isVerified && (
                    <Ionicons
                      name="checkmark-circle"
                      size={16}
                      color="#154733"
                    />
                  )}
                </View>
                {product.user.shopName && (
                  <Text style={styles.shopName}>{product.user.shopName}</Text>
                )}
                <View style={styles.sellerMetaRow}>
                  <Ionicons
                    name="school-outline"
                    size={12}
                    color="#6b7280"
                  />
                  <Text style={styles.sellerMetaText}>Campus seller</Text>
                </View>
              </View>
            </View>

            <View style={styles.sellerStatsRow}>
              <View style={styles.sellerStat}>
                <Text style={styles.sellerStatLabel}>Sold</Text>
                <Text style={styles.sellerStatValue}>—</Text>
              </View>
              <View style={styles.sellerStat}>
                <Text style={styles.sellerStatLabel}>Response time</Text>
                <Text style={styles.sellerStatValue}>Fast</Text>
              </View>
            </View>
          </TouchableOpacity>

          {/* Item Details */}
          <View style={styles.details}>
            <Text style={styles.sectionTitle}>Item Details</Text>
            {product.brand && (
              <View style={styles.detailRow}>
                <Text style={styles.detailLabel}>Brand</Text>
                <Text style={styles.detailValue}>{product.brand}</Text>
              </View>
            )}
            {product.size && (
              <View style={styles.detailRow}>
                <Text style={styles.detailLabel}>Size</Text>
                <Text style={styles.detailValue}>{product.size}</Text>
              </View>
            )}
            <View style={styles.detailRow}>
              <Text style={styles.detailLabel}>Condition</Text>
              <Text style={styles.detailValue}>{product.condition}</Text>
            </View>
            <View style={styles.detailRow}>
              <Text style={styles.detailLabel}>Category</Text>
              <Text style={styles.detailValue}>{product.category}</Text>
            </View>
          </View>

          {/* Description */}
          <View style={styles.description}>
            <Text style={styles.sectionTitle}>Description</Text>
            <Text style={styles.descriptionText}>{product.description}</Text>
          </View>

          {/* Tags */}
          {product.tags && product.tags.length > 0 && (
            <View style={styles.tags}>
              {product.tags.map((tag, index) => (
                <View key={index} style={styles.tag}>
                  <Text style={styles.tagText}>#{tag}</Text>
                </View>
              ))}
            </View>
          )}
        </View>

        {/* Action Buttons - Footer */}
        <View style={styles.footer}>
          <TouchableOpacity
            style={styles.messageButton}
            onPress={handleMessage}
          >
            <Ionicons name="chatbubble-outline" size={18} color="#0f172a" />
            <Text style={styles.messageButtonText}>Message</Text>
          </TouchableOpacity>
          {!isOwner && (
            <TouchableOpacity style={styles.buyButton} onPress={handleBuy}>
              <Ionicons name="bag-outline" size={18} color="#fff" />
              <Text style={styles.buyButtonText}>Buy Now</Text>
            </TouchableOpacity>
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
  backButton: {
    position: 'absolute',
    top: 50,
    left: 15,
    zIndex: 10,
    backgroundColor: 'rgba(255, 255, 255, 0.9)',
    borderRadius: 20,
    width: 40,
    height: 40,
    justifyContent: 'center',
    alignItems: 'center',
    shadowColor: '#000',
    shadowOffset: {
      width: 0,
      height: 2,
    },
    shadowOpacity: 0.25,
    shadowRadius: 3.84,
    elevation: 5,
  },
  menuButton: {
    position: 'absolute',
    top: 50,
    right: 15,
    zIndex: 10,
    backgroundColor: 'rgba(255, 255, 255, 0.9)',
    borderRadius: 20,
    width: 40,
    height: 40,
    justifyContent: 'center',
    alignItems: 'center',
    shadowColor: '#000',
    shadowOffset: {
      width: 0,
      height: 2,
    },
    shadowOpacity: 0.25,
    shadowRadius: 3.84,
    elevation: 5,
  },
  modalOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.5)',
    justifyContent: 'flex-end',
  },
  menuContainer: {
    backgroundColor: '#fff',
    borderTopLeftRadius: 20,
    borderTopRightRadius: 20,
    paddingBottom: 30,
    paddingTop: 10,
  },
  confirmModalContainer: {
    backgroundColor: '#fff',
    borderRadius: 20,
    padding: 20,
    margin: 20,
    maxWidth: 400,
    alignSelf: 'center',
  },
  confirmModalTitle: {
    fontSize: 20,
    fontWeight: 'bold',
    marginBottom: 10,
    textAlign: 'center',
  },
  confirmModalMessage: {
    fontSize: 16,
    color: '#666',
    marginBottom: 20,
    textAlign: 'center',
  },
  confirmModalButtons: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    gap: 10,
  },
  confirmCancelButton: {
    flex: 1,
    padding: 15,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: '#ddd',
    alignItems: 'center',
  },
  confirmCancelText: {
    fontSize: 16,
    fontWeight: '600',
    color: '#000',
  },
  confirmDeleteButton: {
    flex: 1,
    padding: 15,
    borderRadius: 8,
    backgroundColor: '#154733',
    alignItems: 'center',
  },
  confirmDeleteText: {
    fontSize: 16,
    fontWeight: '600',
    color: '#fff',
  },
  buttonDisabled: {
    opacity: 0.6,
  },
  menuItem: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 20,
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
  },
  deleteMenuItem: {
    borderBottomWidth: 0,
  },
  menuItemText: {
    fontSize: 16,
    marginLeft: 15,
    color: '#000',
  },
  deleteText: {
    color: '#154733',
  },
  imageCarousel: {
    width: width,
    height: width,
  },
  imageContainer: {
    width: width,
    height: width,
  },
  mainImage: {
    width: width,
    height: width,
    backgroundColor: '#f0f0f0',
  },
  placeholderContainer: {
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: '#f0f0f0',
  },
  placeholderText: {
    marginTop: 10,
    color: '#999',
    fontSize: 16,
  },
  imageIndicators: {
    flexDirection: 'row',
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: 10,
    backgroundColor: '#fff',
  },
  indicator: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: '#ccc',
    marginHorizontal: 4,
  },
  activeIndicator: {
    backgroundColor: '#154733',
    width: 24,
  },
  scrollContent: {
    flex: 1,
  },
  content: {
    padding: 20,
    paddingBottom: 32,
  },
  priceTitleSection: {
    marginBottom: 16,
  },
  price: {
    fontSize: 30,
    fontWeight: 'bold',
    color: '#000',
  },
  originalPriceRow: {
    flexDirection: 'row',
    alignItems: 'baseline',
    marginTop: 4,
  },
  originalPrice: {
    fontSize: 16,
    color: '#9ca3af',
    textDecorationLine: 'line-through',
    marginRight: 8,
  },
  discountText: {
    fontSize: 14,
    color: '#154733',
    fontWeight: '600',
  },
  title: {
    fontSize: 20,
    fontWeight: '700',
    marginTop: 8,
    color: '#0f172a',
  },
  statsRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 20,
  },
  statsItem: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  statsText: {
    fontSize: 12,
    color: '#6b7280',
    marginLeft: 4,
  },
  statsDot: {
    width: 4,
    height: 4,
    borderRadius: 2,
    backgroundColor: '#e5e7eb',
    marginHorizontal: 10,
  },
  sellerCard: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    padding: 16,
    backgroundColor: '#f8fafc',
    borderRadius: 16,
    marginBottom: 20,
  },
  sellerTopRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    flex: 1,
  },
  sellerAvatarLarge: {
    width: 56,
    height: 56,
    borderRadius: 28,
    marginRight: 12,
  },
  sellerInfoContainer: {
    flex: 1,
  },
  sellerNameRow: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  sellerMetaRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 4,
  },
  sellerMetaText: {
    fontSize: 12,
    color: '#6b7280',
    marginLeft: 4,
  },
  sellerStatsRow: {
    marginTop: 12,
    paddingTop: 12,
    borderBottomWidth: 1,
    borderBottomColor: '#e5e7eb',
    borderTopWidth: 1,
    borderTopColor: '#e5e7eb',
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  sellerStat: {
    flex: 1,
  },
  sellerStatLabel: {
    fontSize: 11,
    color: '#6b7280',
  },
  sellerStatValue: {
    fontSize: 13,
    fontWeight: '600',
    color: '#0f172a',
    marginTop: 2,
  },
  sellerName: {
    fontSize: 16,
    fontWeight: '700',
    color: '#0f172a',
  },
  shopName: {
    fontSize: 14,
    color: '#6b7280',
    marginTop: 2,
  },
  details: {
    marginBottom: 20,
  },
  sectionTitle: {
    fontSize: 13,
    fontWeight: '700',
    marginBottom: 10,
    color: '#9ca3af',
    textTransform: 'uppercase',
  },
  detailRow: {
    flexDirection: 'row',
    marginBottom: 10,
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  detailLabel: {
    fontSize: 14,
    color: '#6b7280',
  },
  detailValue: {
    fontSize: 14,
    fontWeight: '600',
    color: '#0f172a',
  },
  description: {
    marginBottom: 20,
  },
  descriptionText: {
    fontSize: 14,
    lineHeight: 20,
    color: '#374151',
  },
  tags: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    marginBottom: 20,
  },
  tag: {
    backgroundColor: '#f3f4f6',
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 15,
    marginRight: 8,
    marginBottom: 8,
  },
  tagText: {
    fontSize: 12,
    color: '#4b5563',
    fontWeight: '500',
  },
  footer: {
    flexDirection: 'row',
    paddingHorizontal: 20,
    paddingVertical: 16,
    borderTopWidth: 1,
    borderTopColor: '#e5e7eb',
  },
  messageButton: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: '#e5e7eb',
    paddingVertical: 12,
    borderRadius: 12,
    marginRight: 12,
    backgroundColor: '#f3f4f6',
  },
  messageButtonText: {
    fontSize: 14,
    fontWeight: '600',
    color: '#0f172a',
    marginLeft: 6,
  },
  buyButton: {
    flex: 1,
    backgroundColor: '#154733',
    paddingVertical: 12,
    borderRadius: 12,
    alignItems: 'center',
    flexDirection: 'row',
    justifyContent: 'center',
  },
  buyButtonText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '600',
    marginLeft: 6,
  },
  centerContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
});

