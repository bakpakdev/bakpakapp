import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  ScrollView,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  Alert,
  Image,
} from 'react-native';
import { useRoute, useNavigation } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import { api } from '../services/api';

export default function CheckoutScreen() {
  const route = useRoute();
  const navigation = useNavigation();
  const { productId, cartItems } = route.params || {};
  const [products, setProducts] = useState([]);
  const [shippingAddress, setShippingAddress] = useState('');
  const [loading, setLoading] = useState(true);
  const [processing, setProcessing] = useState(false);

  useEffect(() => {
    if (cartItems) {
      // Checkout from cart
      setProducts(cartItems.map(item => ({
        ...item.product,
        quantity: item.quantity,
      })));
      setLoading(false);
    } else if (productId) {
      // Checkout single product
      loadProduct();
    } else {
      setLoading(false);
    }
  }, []);

  const loadProduct = async () => {
    try {
      const response = await api.get(`/products/${productId}`);
      setProducts([{ ...response.data, quantity: 1 }]);
    } catch (error) {
      Alert.alert('Error', 'Failed to load product');
      navigation.goBack();
    } finally {
      setLoading(false);
    }
  };

  const handleCheckout = async () => {
    if (!shippingAddress.trim()) {
      Alert.alert('Error', 'Please enter shipping address');
      return;
    }

    if (products.length === 0) {
      Alert.alert('Error', 'No items to checkout');
      return;
    }

    setProcessing(true);
    try {
      const items = products.map(p => ({
        productId: p.id,
        quantity: p.quantity || 1,
      }));

      const response = await api.post('/orders', {
        items,
        shippingAddress,
      });

      // Clear cart if checking out from cart
      if (cartItems) {
        try {
          await Promise.all(cartItems.map(item => api.delete(`/cart/${item.id}`)));
        } catch (error) {
          console.error('Error clearing cart:', error);
        }
      }

      // Square checkout for this Expo screen is not implemented; native iOS uses Square.
      Alert.alert('Success', 'Order placed successfully!', [
        { text: 'OK', onPress: () => navigation.navigate('Orders') },
      ]);
    } catch (error) {
      Alert.alert('Error', error.response?.data?.message || 'Failed to place order');
    } finally {
      setProcessing(false);
    }
  };

  if (loading || products.length === 0) {
    return (
      <View style={styles.centerContainer}>
        <Text>Loading...</Text>
      </View>
    );
  }

  const calculateTotal = () => {
    return products.reduce((total, product) => {
      return total + (product.price * (product.quantity || 1));
    }, 0);
  };

  const total = calculateTotal();

  return (
    <ScrollView style={styles.container}>
      <View style={styles.header}>
        <TouchableOpacity onPress={() => navigation.goBack()} style={styles.backButton}>
          <Ionicons name="arrow-back" size={24} color="#000" />
        </TouchableOpacity>
        <Text style={styles.headerTitle}>Checkout</Text>
        <View style={styles.backButton} />
      </View>

      {products.map((product, index) => {
        const primaryImage = product.images?.find((img) => img.isPrimary) || product.images?.[0];
        return (
          <View key={product.id || index} style={styles.productSection}>
            <Image
              source={{ uri: primaryImage?.url || 'https://via.placeholder.com/100x100' }}
              style={styles.productImage}
            />
            <View style={styles.productInfo}>
              <Text style={styles.productTitle}>{product.title}</Text>
              <Text style={styles.productPrice}>
                ${product.price.toFixed(2)} {product.quantity > 1 && `x ${product.quantity}`}
              </Text>
            </View>
          </View>
        );
      })}

      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Shipping Address</Text>
        <TextInput
          style={styles.textArea}
          value={shippingAddress}
          onChangeText={setShippingAddress}
          placeholder="Enter your shipping address"
          multiline
          numberOfLines={4}
        />
      </View>

      <View style={styles.summary}>
        <View style={styles.summaryRow}>
          <Text style={styles.summaryLabel}>Subtotal</Text>
          <Text style={styles.summaryValue}>${total.toFixed(2)}</Text>
        </View>
        <View style={styles.summaryRow}>
          <Text style={styles.summaryLabel}>Shipping</Text>
          <Text style={styles.summaryValue}>$0.00</Text>
        </View>
        <View style={[styles.summaryRow, styles.totalRow]}>
          <Text style={styles.totalLabel}>Total</Text>
          <Text style={styles.totalValue}>${total.toFixed(2)}</Text>
        </View>
      </View>

      <TouchableOpacity
        style={[styles.checkoutButton, processing && styles.buttonDisabled]}
        onPress={handleCheckout}
        disabled={processing}
      >
        <Text style={styles.checkoutButtonText}>
          {processing ? 'Processing...' : 'Complete Purchase'}
        </Text>
      </TouchableOpacity>
    </ScrollView>
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
  productSection: {
    flexDirection: 'row',
    padding: 15,
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
  },
  productImage: {
    width: 100,
    height: 100,
    borderRadius: 8,
    marginRight: 15,
  },
  productInfo: {
    flex: 1,
    justifyContent: 'center',
  },
  productTitle: {
    fontSize: 16,
    fontWeight: '600',
    marginBottom: 5,
  },
  productPrice: {
    fontSize: 18,
    fontWeight: 'bold',
  },
  section: {
    padding: 15,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '600',
    marginBottom: 10,
  },
  textArea: {
    borderWidth: 1,
    borderColor: '#ddd',
    borderRadius: 8,
    padding: 12,
    height: 100,
    textAlignVertical: 'top',
  },
  summary: {
    padding: 15,
    borderTopWidth: 1,
    borderTopColor: '#eee',
  },
  summaryRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: 10,
  },
  summaryLabel: {
    fontSize: 14,
    color: '#666',
  },
  summaryValue: {
    fontSize: 14,
    fontWeight: '500',
  },
  totalRow: {
    marginTop: 10,
    paddingTop: 10,
    borderTopWidth: 1,
    borderTopColor: '#eee',
  },
  totalLabel: {
    fontSize: 18,
    fontWeight: '600',
  },
  totalValue: {
    fontSize: 18,
    fontWeight: 'bold',
  },
  checkoutButton: {
    backgroundColor: '#154733',
    padding: 15,
    margin: 15,
    borderRadius: 8,
    alignItems: 'center',
  },
  buttonDisabled: {
    opacity: 0.6,
  },
  checkoutButtonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
  centerContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
});

