import React, { useState, useEffect, useContext } from 'react';
import {
  View,
  Text,
  FlatList,
  Image,
  TouchableOpacity,
  StyleSheet,
  Alert,
  ScrollView,
  RefreshControl,
} from 'react-native';
import { useNavigation, useFocusEffect } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import { api } from '../services/api';
import { AuthContext } from '../context/AuthContext';

export default function CartScreen() {
  const navigation = useNavigation();
  const { user } = useContext(AuthContext);
  const [cartItems, setCartItems] = useState([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  useFocusEffect(
    React.useCallback(() => {
      loadCart();
    }, [])
  );

  const loadCart = async () => {
    try {
      const response = await api.get('/cart');
      setCartItems(response.data);
    } catch (error) {
      console.error('Error loading cart:', error);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  };

  const onRefresh = () => {
    setRefreshing(true);
    loadCart();
  };

  const updateQuantity = async (itemId, newQuantity) => {
    if (newQuantity < 1) {
      removeItem(itemId);
      return;
    }

    try {
      await api.put(`/cart/${itemId}`, { quantity: newQuantity });
      loadCart();
    } catch (error) {
      console.error('Error updating quantity:', error);
      Alert.alert('Error', 'Failed to update quantity');
    }
  };

  const removeItem = async (itemId) => {
    try {
      await api.delete(`/cart/${itemId}`);
      loadCart();
    } catch (error) {
      console.error('Error removing item:', error);
      Alert.alert('Error', 'Failed to remove item');
    }
  };

  const handleCheckout = () => {
    if (cartItems.length === 0) {
      Alert.alert('Cart Empty', 'Your cart is empty');
      return;
    }

    // Navigate to checkout with cart items
    navigation.navigate('Checkout', { cartItems });
  };

  const calculateTotal = () => {
    return cartItems.reduce((total, item) => {
      return total + (item.product.price * item.quantity);
    }, 0);
  };

  const renderCartItem = ({ item }) => {
    const primaryImage = item.product.images?.find((img) => img.isPrimary) || item.product.images?.[0];

    return (
      <View style={styles.cartItem}>
        <Image
          source={{ uri: primaryImage?.url || 'https://via.placeholder.com/100x100' }}
          style={styles.itemImage}
        />
        <View style={styles.itemInfo}>
          <TouchableOpacity
            onPress={() => navigation.navigate('ProductDetail', { productId: item.product.id })}
          >
            <Text style={styles.itemTitle} numberOfLines={2}>
              {item.product.title}
            </Text>
            <Text style={styles.itemPrice}>${item.product.price.toFixed(2)}</Text>
            <Text style={styles.itemSeller}>by {item.product.user?.username}</Text>
          </TouchableOpacity>
          
          <View style={styles.quantityContainer}>
            <TouchableOpacity
              style={styles.quantityButton}
              onPress={() => updateQuantity(item.id, item.quantity - 1)}
            >
              <Ionicons name="remove" size={20} color="#000" />
            </TouchableOpacity>
            <Text style={styles.quantityText}>{item.quantity}</Text>
            <TouchableOpacity
              style={styles.quantityButton}
              onPress={() => updateQuantity(item.id, item.quantity + 1)}
            >
              <Ionicons name="add" size={20} color="#000" />
            </TouchableOpacity>
            <TouchableOpacity
              style={styles.removeButton}
              onPress={() => removeItem(item.id)}
            >
              <Ionicons name="trash-outline" size={20} color="#ff4444" />
            </TouchableOpacity>
          </View>
        </View>
      </View>
    );
  };

  if (loading) {
    return (
      <View style={styles.centerContainer}>
        <Text>Loading...</Text>
      </View>
    );
  }

  const total = calculateTotal();

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <TouchableOpacity onPress={() => navigation.goBack()} style={styles.backButton}>
          <Ionicons name="arrow-back" size={24} color="#000" />
        </TouchableOpacity>
        <Text style={styles.headerTitle}>Shopping Bag</Text>
        <View style={styles.backButton} />
      </View>

      {cartItems.length === 0 ? (
        <View style={styles.emptyContainer}>
          <Ionicons name="basket-outline" size={64} color="#ccc" />
          <Text style={styles.emptyText}>Your bag is empty</Text>
          <Text style={styles.emptySubtext}>Add items to get started</Text>
        </View>
      ) : (
        <>
          <FlatList
            data={cartItems}
            renderItem={renderCartItem}
            keyExtractor={(item) => item.id}
            contentContainerStyle={styles.list}
            refreshControl={
              <RefreshControl refreshing={refreshing} onRefresh={onRefresh} />
            }
          />
          <View style={styles.footer}>
            <View style={styles.totalContainer}>
              <Text style={styles.totalLabel}>Total</Text>
              <Text style={styles.totalAmount}>${total.toFixed(2)}</Text>
            </View>
            <TouchableOpacity style={styles.checkoutButton} onPress={handleCheckout}>
              <Text style={styles.checkoutButtonText}>Checkout</Text>
            </TouchableOpacity>
          </View>
        </>
      )}
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
    flexDirection: 'row',
    alignItems: 'center',
    padding: 15,
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
  },
  backButton: {
    padding: 5,
    width: 34,
  },
  headerTitle: {
    fontSize: 28,
    fontWeight: 'bold',
    flex: 1,
    textAlign: 'center',
  },
  list: {
    padding: 15,
  },
  cartItem: {
    flexDirection: 'row',
    backgroundColor: '#fff',
    borderRadius: 8,
    marginBottom: 15,
    padding: 15,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 3,
  },
  itemImage: {
    width: 100,
    height: 100,
    borderRadius: 8,
    backgroundColor: '#f0f0f0',
    marginRight: 15,
  },
  itemInfo: {
    flex: 1,
  },
  itemTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: '#333',
    marginBottom: 5,
  },
  itemPrice: {
    fontSize: 18,
    fontWeight: 'bold',
    color: '#000',
    marginBottom: 5,
  },
  itemSeller: {
    fontSize: 12,
    color: '#666',
    marginBottom: 10,
  },
  quantityContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 10,
  },
  quantityButton: {
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: '#f0f0f0',
    justifyContent: 'center',
    alignItems: 'center',
  },
  quantityText: {
    fontSize: 16,
    fontWeight: '600',
    marginHorizontal: 15,
    minWidth: 30,
    textAlign: 'center',
  },
  removeButton: {
    marginLeft: 'auto',
    padding: 5,
  },
  footer: {
    borderTopWidth: 1,
    borderTopColor: '#eee',
    padding: 15,
    backgroundColor: '#fff',
  },
  totalContainer: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 15,
  },
  totalLabel: {
    fontSize: 18,
    fontWeight: '600',
    color: '#333',
  },
  totalAmount: {
    fontSize: 24,
    fontWeight: 'bold',
    color: '#000',
  },
  checkoutButton: {
    backgroundColor: '#154733',
    padding: 15,
    borderRadius: 8,
    alignItems: 'center',
  },
  checkoutButtonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
  emptyContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  emptyText: {
    fontSize: 18,
    fontWeight: '600',
    color: '#333',
    marginTop: 20,
    marginBottom: 8,
  },
  emptySubtext: {
    fontSize: 14,
    color: '#666',
  },
  centerContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
});

