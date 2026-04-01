import React, { useContext, useState, useRef } from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
  ScrollView,
  Image,
  Alert,
  Dimensions,
  Platform,
  Modal,
  Animated,
  FlatList,
} from 'react-native';
import { useNavigation, useFocusEffect } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import { AuthContext } from '../context/AuthContext';
import { api } from '../services/api';
import { LinearGradient } from 'expo-linear-gradient';

const { width } = Dimensions.get('window');
const feedItemSize = (width - 0.5) / 3; // 3 columns with 0.5px gaps

export default function ProfileScreen() {
  const { user, logout } = useContext(AuthContext);
  const navigation = useNavigation();
  const [stats, setStats] = useState({ products: 0, followers: 0, following: 0 });
  const [products, setProducts] = useState([]);
  const [likedItems, setLikedItems] = useState([]);
  const [savedItems, setSavedItems] = useState([]);
  const [activeTab, setActiveTab] = useState('shop');
  const [loadingListings, setLoadingListings] = useState(true);
  const [loadingLiked, setLoadingLiked] = useState(false);
  const [loadingSaved, setLoadingSaved] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);
  const [showLogoutModal, setShowLogoutModal] = useState(false);
  const [userProfile, setUserProfile] = useState(null);
  
  const tabUnderlineAnim = useRef(new Animated.Value(0)).current;

  useFocusEffect(
    React.useCallback(() => {
      loadStats();
      loadProducts();
      if (activeTab === 'likes') {
        loadLikedItems();
      } else if (activeTab === 'saved') {
        loadSavedItems();
      }
    }, [user?.id, activeTab])
  );

  const loadStats = async () => {
    try {
      const response = await api.get(`/users/${user.id}`);
      setUserProfile(response.data);
      setStats({
        products: response.data._count?.products || 0,
        followers: response.data._count?.followers || 0,
        following: response.data._count?.following || 0,
      });
    } catch (error) {
      console.error('Error loading stats:', error);
    }
  };

  const loadProducts = async () => {
    try {
      setLoadingListings(true);
      const response = await api.get(`/users/${user.id}/products`);
      setProducts(response.data || []);
    } catch (error) {
      console.error('Error loading user listings for profile:', error);
    } finally {
      setLoadingListings(false);
    }
  };

  const loadLikedItems = async () => {
    try {
      setLoadingLiked(true);
      const response = await api.get('/social/liked');
      setLikedItems(response.data || []);
    } catch (error) {
      console.error('Error loading liked items:', error);
    } finally {
      setLoadingLiked(false);
    }
  };

  const loadSavedItems = async () => {
    try {
      setLoadingSaved(true);
      const response = await api.get('/social/saved');
      setSavedItems(response.data || []);
    } catch (error) {
      console.error('Error loading saved items:', error);
    } finally {
      setLoadingSaved(false);
    }
  };

  const handleTabChange = (tab) => {
    setActiveTab(tab);
    const tabIndex = ['shop', 'likes', 'saved', 'reviews'].indexOf(tab);
    Animated.timing(tabUnderlineAnim, {
      toValue: tabIndex,
      duration: 200,
      useNativeDriver: Platform.OS !== 'web',
    }).start();

    if (tab === 'likes' && likedItems.length === 0) {
      loadLikedItems();
    } else if (tab === 'saved' && savedItems.length === 0) {
      loadSavedItems();
    }
  };

  const handleLogout = () => {
    setMenuOpen(false);
    setShowLogoutModal(true);
  };

  const confirmLogout = async () => {
    setShowLogoutModal(false);
    try {
      await logout();
    } catch (error) {
      console.error('Logout error:', error);
      Alert.alert('Error', 'Failed to logout. Please try again.');
    }
  };

  const cancelLogout = () => {
    setShowLogoutModal(false);
  };

  const renderProduct = (item) => {
    const primaryImage = item.images?.find((img) => img.isPrimary) || item.images?.[0];
    return (
      <TouchableOpacity
        key={item.id}
        style={styles.feedItem}
        onPress={() => navigation.navigate('ProductDetail', { productId: item.id })}
        activeOpacity={0.9}
      >
        <Image
          source={{
            uri: primaryImage?.url || 'https://via.placeholder.com/200x200',
          }}
          style={styles.feedImage}
        />
        {item.isSold && (
          <View style={styles.soldOverlay}>
            <View style={styles.soldBadge}>
              <Text style={styles.soldText}>SOLD</Text>
            </View>
          </View>
        )}
        <LinearGradient
          colors={['transparent', 'rgba(0,0,0,0.6)']}
          style={styles.priceGradient}
        >
          <Text style={styles.itemPrice}>${Number(item.price || 0).toFixed(2)}</Text>
        </LinearGradient>
      </TouchableOpacity>
    );
  };

  const getCurrentItems = () => {
    if (activeTab === 'shop') return products;
    if (activeTab === 'likes') return likedItems;
    if (activeTab === 'saved') return savedItems;
    return [];
  };

  const getCurrentLoading = () => {
    if (activeTab === 'shop') return loadingListings;
    if (activeTab === 'likes') return loadingLiked;
    if (activeTab === 'saved') return loadingSaved;
    return false;
  };

  const tabUnderlinePosition = tabUnderlineAnim.interpolate({
    inputRange: [0, 1, 2, 3],
    outputRange: ['0%', '25%', '50%', '75%'],
  });

  const rating = userProfile?.rating || 4.8; // Fallback if not available
  const reviewCount = userProfile?.reviewCount || 0;
  const soldCount = userProfile?._count?.soldProducts || stats.products || 0;
  const university = userProfile?.university || user?.college || 'University of Oregon';
  const activeStatus = 'Active today'; // Could be calculated from last activity
  const displayName = user?.shopName || user?.username || user?.firstName || user?.username || 'User';

  return (
    <View style={styles.container}>
      {/* Sticky Header */}
      <View style={styles.header}>
        <View style={styles.headerTopRow}>
          <View style={styles.headerLeft}>
            <TouchableOpacity onPress={() => navigation.goBack()} style={styles.headerButton}>
              <Ionicons name="arrow-back" size={24} color="#111827" />
            </TouchableOpacity>
            <Text style={styles.headerUsername}>@{user?.username || ''}</Text>
          </View>
          <View style={styles.headerRight}>
            <TouchableOpacity style={styles.headerButton}>
              <Ionicons name="share-outline" size={20} color="#374151" />
            </TouchableOpacity>
            <TouchableOpacity
              style={styles.headerButton}
              onPress={() => navigation.navigate('EditProfile')}
            >
              <Ionicons name="settings-outline" size={20} color="#374151" />
            </TouchableOpacity>
            <TouchableOpacity
              style={styles.headerButton}
              onPress={() => setMenuOpen(!menuOpen)}
            >
              <Ionicons name="ellipsis-horizontal" size={20} color="#374151" />
            </TouchableOpacity>
          </View>
        </View>

        {menuOpen && (
          <View style={styles.dropdownMenu}>
            <TouchableOpacity
              style={styles.dropdownItem}
              onPress={() => {
                setMenuOpen(false);
                navigation.navigate('SavedItems');
              }}
            >
              <Ionicons name="bookmark-outline" size={20} color="#000" />
              <Text style={styles.dropdownText}>Saved Items</Text>
            </TouchableOpacity>

            <TouchableOpacity
              style={styles.dropdownItem}
              onPress={() => {
                setMenuOpen(false);
                navigation.navigate('LikedItems');
              }}
            >
              <Ionicons name="heart-outline" size={20} color="#000" />
              <Text style={styles.dropdownText}>Liked Items</Text>
            </TouchableOpacity>

            <TouchableOpacity
              style={styles.dropdownItem}
              onPress={() => {
                setMenuOpen(false);
                navigation.navigate('Orders');
              }}
            >
              <Ionicons name="receipt-outline" size={20} color="#000" />
              <Text style={styles.dropdownText}>Orders</Text>
            </TouchableOpacity>

            <TouchableOpacity
              style={styles.dropdownItem}
              activeOpacity={0.7}
              onPress={handleLogout}
            >
              <Ionicons name="log-out-outline" size={20} color="#ff4444" />
              <Text style={[styles.dropdownText, styles.logoutText]}>Logout</Text>
            </TouchableOpacity>
          </View>
        )}
      </View>

      {/* Tabs */}
      <View style={styles.tabsContainer}>
        {['Shop', 'Likes', 'Saved', 'Reviews'].map((tab, index) => {
          const tabKey = tab.toLowerCase();
          return (
            <TouchableOpacity
              key={tab}
              style={styles.tab}
              onPress={() => handleTabChange(tabKey)}
              activeOpacity={0.7}
            >
              <Text
                style={[
                  styles.tabText,
                  activeTab === tabKey && styles.tabTextActive,
                ]}
              >
                {tab}
              </Text>
            </TouchableOpacity>
          );
        })}
        <Animated.View
          style={[
            styles.tabUnderline,
            {
              left: tabUnderlinePosition,
            },
          ]}
        />
      </View>

      <ScrollView
        style={styles.scrollView}
        contentContainerStyle={styles.scrollContent}
        showsVerticalScrollIndicator={false}
      >
        {/* Profile Info */}
        <View style={styles.profileSection}>
          <View style={styles.profileTopRow}>
            <View style={styles.avatarContainer}>
              <Image
                source={{ uri: user?.avatar || 'https://via.placeholder.com/80' }}
                style={styles.avatar}
              />
              {user?.isVerified && (
                <View style={styles.verifiedBadge}>
                  <Ionicons name="shield-checkmark" size={12} color="#fff" />
                </View>
              )}
            </View>
            <View style={styles.profileInfo}>
              <Text style={styles.displayName}>{displayName}</Text>
              <View style={styles.ratingRow}>
                <View style={styles.starsContainer}>
                  {[...Array(5)].map((_, i) => (
                    <Ionicons
                      key={i}
                      name={i < Math.floor(rating) ? 'star' : 'star-outline'}
                      size={12}
                      color={i < Math.floor(rating) ? '#154733' : '#e5e7eb'}
                      style={styles.star}
                    />
                  ))}
                </View>
                <Text style={styles.reviewCount}>({reviewCount})</Text>
              </View>
              <View style={styles.badgesRow}>
                <View style={styles.universityBadge}>
                  <Ionicons name="location-outline" size={12} color="#154733" />
                  <Text style={styles.universityText}>{university}</Text>
                </View>
                <View style={styles.activeBadge}>
                  <Ionicons name="flash-outline" size={12} color="#FEE11A" />
                  <Text style={styles.activeText}>{activeStatus}</Text>
                </View>
              </View>
            </View>
          </View>

          <View style={styles.soldContainer}>
            <View style={styles.soldBadgeContainer}>
              <Ionicons name="cube-outline" size={16} color="#6b7280" />
              <Text style={styles.soldCount}>
                <Text style={styles.soldNumber}>{soldCount}</Text> sold
              </Text>
            </View>
          </View>

          {user?.bio && (
            <Text style={styles.bio}>{user.bio}</Text>
          )}

          <View style={styles.statsRow}>
            <View style={styles.statItem}>
              <Text style={styles.statNumber}>{stats.followers}</Text>
              <Text style={styles.statLabel}>followers</Text>
            </View>
            <View style={styles.statsDivider} />
            <View style={styles.statItem}>
              <Text style={styles.statNumber}>{stats.following}</Text>
              <Text style={styles.statLabel}>following</Text>
            </View>
          </View>

          <TouchableOpacity
            style={styles.editButton}
            onPress={() => navigation.navigate('EditProfile')}
            activeOpacity={0.8}
          >
            <Text style={styles.editButtonText}>Edit Profile</Text>
          </TouchableOpacity>
        </View>

        {/* Listings Grid */}
        {getCurrentLoading() ? (
          <View style={styles.loadingContainer}>
            <Text style={styles.loadingText}>Loading...</Text>
          </View>
        ) : getCurrentItems().length === 0 ? (
          <View style={styles.emptyContainer}>
            <Text style={styles.emptyText}>
              {activeTab === 'shop' && 'You don\'t have any listings yet.'}
              {activeTab === 'likes' && 'No liked items yet.'}
              {activeTab === 'saved' && 'No saved items yet.'}
              {activeTab === 'reviews' && 'No reviews yet.'}
            </Text>
          </View>
        ) : (
          <View style={styles.gridContainer}>
            <View style={styles.grid}>
              {getCurrentItems().map((item) => renderProduct(item))}
            </View>
          </View>
        )}

      </ScrollView>

      {/* Logout Confirmation Modal */}
      <Modal
        visible={showLogoutModal}
        transparent={true}
        animationType="fade"
        onRequestClose={cancelLogout}
      >
        <View style={styles.modalOverlay}>
          <View style={styles.logoutModalContainer}>
            <Text style={styles.logoutModalTitle}>Logout</Text>
            <Text style={styles.logoutModalMessage}>
              Are you sure you want to logout?
            </Text>
            <View style={styles.logoutModalButtons}>
              <TouchableOpacity
                style={styles.logoutCancelButton}
                onPress={cancelLogout}
              >
                <Text style={styles.logoutCancelText}>Cancel</Text>
              </TouchableOpacity>
              <TouchableOpacity
                style={styles.logoutConfirmButton}
                onPress={confirmLogout}
              >
                <Text style={styles.logoutConfirmText}>Logout</Text>
              </TouchableOpacity>
            </View>
          </View>
        </View>
      </Modal>
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
    borderBottomWidth: 1,
    borderBottomColor: '#f3f4f6',
    paddingTop: Platform.OS === 'ios' ? 50 : 20,
    paddingBottom: 12,
    paddingHorizontal: 16,
    position: 'relative',
  },
  headerTopRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  headerLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    flex: 1,
  },
  headerRight: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  headerButton: {
    padding: 8,
  },
  headerUsername: {
    fontSize: 18,
    fontWeight: 'bold',
    color: '#111827',
    marginLeft: 12,
  },
  dropdownMenu: {
    position: 'absolute',
    top: Platform.OS === 'ios' ? 90 : 60,
    right: 16,
    backgroundColor: '#fff',
    borderRadius: 8,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.15,
    shadowRadius: 6,
    elevation: 4,
    paddingVertical: 4,
    minWidth: 180,
    zIndex: 10,
  },
  dropdownItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
  dropdownText: {
    marginLeft: 10,
    fontSize: 15,
    flex: 1,
  },
  logoutText: {
    color: '#154733',
  },
  tabsContainer: {
    flexDirection: 'row',
    borderBottomWidth: 1,
    borderBottomColor: '#f3f4f6',
    backgroundColor: '#fff',
    position: 'relative',
  },
  tab: {
    flex: 1,
    paddingVertical: 12,
    alignItems: 'center',
  },
  tabText: {
    fontSize: 14,
    fontWeight: '600',
    color: '#9ca3af',
  },
  tabTextActive: {
    color: '#111827',
  },
  tabUnderline: {
    position: 'absolute',
    bottom: 0,
    width: '25%',
    height: 2,
    backgroundColor: '#154733',
  },
  scrollView: {
    flex: 1,
  },
  scrollContent: {
    paddingBottom: 20,
  },
  profileSection: {
    paddingHorizontal: 20,
    paddingTop: 24,
    paddingBottom: 20,
  },
  profileTopRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    marginBottom: 16,
  },
  avatarContainer: {
    position: 'relative',
    marginRight: 20,
  },
  avatar: {
    width: 80,
    height: 80,
    borderRadius: 40,
    borderWidth: 2,
    borderColor: '#f9fafb',
  },
  verifiedBadge: {
    position: 'absolute',
    bottom: 0,
    right: 0,
    backgroundColor: '#154733',
    borderRadius: 12,
    padding: 2,
    borderWidth: 2,
    borderColor: '#fff',
  },
  profileInfo: {
    flex: 1,
  },
  displayName: {
    fontSize: 20,
    fontWeight: 'bold',
    color: '#111827',
    marginBottom: 4,
  },
  ratingRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 8,
  },
  starsContainer: {
    flexDirection: 'row',
    marginRight: 4,
  },
  star: {
    marginRight: 2,
  },
  reviewCount: {
    fontSize: 12,
    fontWeight: 'bold',
    color: '#6b7280',
  },
  badgesRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
    marginTop: 4,
  },
  universityBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#e6f2ed',
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 12,
    gap: 4,
  },
  universityText: {
    fontSize: 10,
    fontWeight: 'bold',
    color: '#154733',
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },
  activeBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#fef9e7',
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 12,
    gap: 4,
  },
  activeText: {
    fontSize: 10,
    fontWeight: 'bold',
    color: '#b8860b',
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },
  soldContainer: {
    marginBottom: 16,
  },
  soldBadgeContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#f9fafb',
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 8,
    alignSelf: 'flex-start',
    gap: 6,
  },
  soldCount: {
    fontSize: 12,
    color: '#6b7280',
    fontWeight: '500',
  },
  soldNumber: {
    fontWeight: 'bold',
    color: '#111827',
  },
  bio: {
    fontSize: 14,
    color: '#6b7280',
    lineHeight: 20,
    marginBottom: 24,
  },
  statsRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 24,
  },
  statItem: {
    alignItems: 'flex-start',
  },
  statNumber: {
    fontSize: 18,
    fontWeight: 'bold',
    color: '#111827',
    marginBottom: 2,
  },
  statLabel: {
    fontSize: 12,
    color: '#6b7280',
    fontWeight: '500',
    textTransform: 'lowercase',
  },
  statsDivider: {
    width: 1,
    height: 40,
    backgroundColor: '#e5e7eb',
    marginHorizontal: 24,
  },
  editButton: {
    backgroundColor: '#154733',
    paddingVertical: 12,
    paddingHorizontal: 24,
    borderRadius: 8,
    alignItems: 'center',
    shadowColor: '#154733',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 2,
  },
  editButtonText: {
    fontSize: 14,
    fontWeight: 'bold',
    color: '#fff',
  },
  loadingContainer: {
    padding: 40,
    alignItems: 'center',
  },
  loadingText: {
    fontSize: 14,
    color: '#6b7280',
  },
  emptyContainer: {
    padding: 40,
    alignItems: 'center',
  },
  emptyText: {
    fontSize: 14,
    color: '#6b7280',
  },
  gridContainer: {
    backgroundColor: '#f3f4f6',
  },
  grid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    marginHorizontal: -0.25,
  },
  feedItem: {
    width: feedItemSize,
    height: feedItemSize * 1.33, // 4:3 aspect ratio
    margin: 0.25,
    backgroundColor: '#fff',
    position: 'relative',
    overflow: 'hidden',
  },
  feedImage: {
    width: '100%',
    height: '100%',
  },
  soldOverlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: 'rgba(255, 255, 255, 0.2)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  soldBadge: {
    backgroundColor: 'rgba(255, 255, 255, 0.9)',
    paddingHorizontal: 12,
    paddingVertical: 4,
    borderRadius: 4,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.1,
    shadowRadius: 2,
    elevation: 2,
  },
  soldText: {
    fontSize: 10,
    fontWeight: '900',
    color: '#111827',
    letterSpacing: 2,
    textTransform: 'uppercase',
  },
  priceGradient: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    padding: 8,
    justifyContent: 'flex-end',
  },
  itemPrice: {
    color: '#fff',
    fontSize: 12,
    fontWeight: 'bold',
  },
  modalOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.5)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  logoutModalContainer: {
    backgroundColor: '#fff',
    borderRadius: 20,
    padding: 24,
    margin: 20,
    minWidth: 300,
    maxWidth: 400,
    alignSelf: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.25,
    shadowRadius: 8,
    elevation: 5,
  },
  logoutModalTitle: {
    fontSize: 22,
    fontWeight: 'bold',
    marginBottom: 12,
    textAlign: 'center',
    color: '#000',
  },
  logoutModalMessage: {
    fontSize: 16,
    color: '#666',
    marginBottom: 24,
    textAlign: 'center',
    lineHeight: 22,
  },
  logoutModalButtons: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    gap: 12,
  },
  logoutCancelButton: {
    flex: 1,
    padding: 14,
    borderRadius: 10,
    borderWidth: 1.5,
    borderColor: '#ddd',
    alignItems: 'center',
    backgroundColor: '#fff',
  },
  logoutCancelText: {
    fontSize: 16,
    fontWeight: '600',
    color: '#000',
  },
  logoutConfirmButton: {
    flex: 1,
    padding: 14,
    borderRadius: 10,
    alignItems: 'center',
    backgroundColor: '#000',
  },
  logoutConfirmText: {
    fontSize: 16,
    fontWeight: '600',
    color: '#fff',
  },
});
