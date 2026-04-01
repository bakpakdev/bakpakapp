import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  FlatList,
  Image,
  TouchableOpacity,
  StyleSheet,
  Dimensions,
} from 'react-native';
import { useRoute, useNavigation } from '@react-navigation/native';
import { api } from '../services/api';
import { Ionicons } from '@expo/vector-icons';

const { width } = Dimensions.get('window');
const itemWidth = (width - 30) / 2;

export default function UserProfileScreen() {
  const route = useRoute();
  const { userId } = route.params;
  const navigation = useNavigation();
  const [user, setUser] = useState(null);
  const [products, setProducts] = useState([]);
  const [following, setFollowing] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    loadUser();
    loadProducts();
    checkFollowing();
  }, [userId]);

  const loadUser = async () => {
    try {
      const response = await api.get(`/users/${userId}`);
      setUser(response.data);
    } catch (error) {
      console.error('Error loading user:', error);
    } finally {
      setLoading(false);
    }
  };

  const loadProducts = async () => {
    try {
      const response = await api.get(`/users/${userId}/products`);
      setProducts(response.data);
    } catch (error) {
      console.error('Error loading products:', error);
    }
  };

  const checkFollowing = async () => {
    try {
      // Check if following logic would go here
    } catch (error) {
      // Ignore
    }
  };

  const handleFollow = async () => {
    try {
      if (following) {
        await api.delete(`/social/follow/${userId}`);
        setFollowing(false);
      } else {
        await api.post(`/social/follow/${userId}`);
        setFollowing(true);
      }
    } catch (error) {
      console.error('Follow error:', error);
    }
  };

  const renderProduct = ({ item }) => {
    const primaryImage = item.images?.find((img) => img.isPrimary) || item.images?.[0];

    return (
      <TouchableOpacity
        style={styles.productCard}
        onPress={() => navigation.navigate('ProductDetail', { productId: item.id })}
      >
        <Image
          source={{ uri: primaryImage?.url || 'https://via.placeholder.com/200x200' }}
          style={styles.productImage}
        />
        <Text style={styles.productPrice}>${item.price}</Text>
      </TouchableOpacity>
    );
  };

  if (loading || !user) {
    return (
      <View style={styles.centerContainer}>
        <Text>Loading...</Text>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <Image
          source={{ uri: user.avatar || 'https://via.placeholder.com/80' }}
          style={styles.avatar}
        />
        <Text style={styles.username}>{user.username}</Text>
        {user.shopName && <Text style={styles.shopName}>{user.shopName}</Text>}
        {user.bio && <Text style={styles.bio}>{user.bio}</Text>}

        <TouchableOpacity
          style={[styles.followButton, following && styles.followingButton]}
          onPress={handleFollow}
        >
          <Text style={[styles.followButtonText, following && styles.followingButtonText]}>
            {following ? 'Following' : 'Follow'}
          </Text>
        </TouchableOpacity>
      </View>

      <View style={styles.stats}>
        <View style={styles.statItem}>
          <Text style={styles.statNumber}>{user._count?.products || 0}</Text>
          <Text style={styles.statLabel}>Listings</Text>
        </View>
        <View style={styles.statItem}>
          <Text style={styles.statNumber}>{user._count?.followers || 0}</Text>
          <Text style={styles.statLabel}>Followers</Text>
        </View>
        <View style={styles.statItem}>
          <Text style={styles.statNumber}>{user._count?.following || 0}</Text>
          <Text style={styles.statLabel}>Following</Text>
        </View>
      </View>

      <FlatList
        data={products}
        renderItem={renderProduct}
        keyExtractor={(item) => item.id}
        numColumns={2}
        contentContainerStyle={styles.list}
        ListHeaderComponent={<Text style={styles.sectionTitle}>Listings</Text>}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
    paddingTop: 50,
  },
  header: {
    padding: 20,
    alignItems: 'center',
  },
  avatar: {
    width: 80,
    height: 80,
    borderRadius: 40,
    marginBottom: 10,
  },
  username: {
    fontSize: 24,
    fontWeight: 'bold',
    marginBottom: 5,
  },
  shopName: {
    fontSize: 16,
    color: '#666',
    marginBottom: 5,
  },
  bio: {
    fontSize: 14,
    color: '#666',
    textAlign: 'center',
    marginTop: 10,
    marginBottom: 15,
  },
  followButton: {
    borderWidth: 1,
    borderColor: '#000',
    paddingHorizontal: 30,
    paddingVertical: 10,
    borderRadius: 8,
    marginTop: 10,
  },
  followingButton: {
    backgroundColor: '#154733',
  },
  followButtonText: {
    fontSize: 14,
    fontWeight: '600',
  },
  followingButtonText: {
    color: '#fff',
  },
  stats: {
    flexDirection: 'row',
    justifyContent: 'space-around',
    paddingVertical: 20,
    borderTopWidth: 1,
    borderBottomWidth: 1,
    borderColor: '#eee',
  },
  statItem: {
    alignItems: 'center',
  },
  statNumber: {
    fontSize: 20,
    fontWeight: 'bold',
    marginBottom: 5,
  },
  statLabel: {
    fontSize: 14,
    color: '#666',
  },
  list: {
    padding: 10,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '600',
    padding: 15,
    paddingBottom: 10,
  },
  productCard: {
    width: itemWidth,
    margin: 5,
    backgroundColor: '#fff',
    borderRadius: 8,
    overflow: 'hidden',
  },
  productImage: {
    width: '100%',
    height: itemWidth,
    backgroundColor: '#f0f0f0',
  },
  productPrice: {
    padding: 10,
    fontSize: 16,
    fontWeight: 'bold',
  },
  centerContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
});

