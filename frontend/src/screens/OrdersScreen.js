import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  FlatList,
  TouchableOpacity,
  StyleSheet,
  Image,
} from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import { api } from '../services/api';

export default function OrdersScreen() {
  const [orders, setOrders] = useState([]);
  const [loading, setLoading] = useState(true);
  const navigation = useNavigation();

  useEffect(() => {
    loadOrders();
  }, []);

  const loadOrders = async () => {
    try {
      const response = await api.get('/orders');
      setOrders(response.data);
    } catch (error) {
      console.error('Error loading orders:', error);
    } finally {
      setLoading(false);
    }
  };

  const renderOrder = ({ item }) => {
    const primaryItem = item.items[0];
    const primaryImage = primaryItem?.product?.images?.[0];

    return (
      <TouchableOpacity style={styles.orderCard}>
        <View style={styles.orderHeader}>
          <Text style={styles.orderId}>Order #{item.id.slice(0, 8)}</Text>
          <Text style={styles.orderStatus}>{item.status}</Text>
        </View>
        <View style={styles.orderContent}>
          {primaryImage && (
            <Image
              source={{ uri: primaryImage.url || 'https://via.placeholder.com/80' }}
              style={styles.orderImage}
            />
          )}
          <View style={styles.orderInfo}>
            <Text style={styles.orderTitle}>
              {item.items.length} item{item.items.length > 1 ? 's' : ''}
            </Text>
            <Text style={styles.orderDate}>
              {new Date(item.createdAt).toLocaleDateString()}
            </Text>
            <Text style={styles.orderTotal}>${item.total.toFixed(2)}</Text>
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
      <View style={styles.header}>
        <TouchableOpacity onPress={() => navigation.goBack()} style={styles.backButton}>
          <Ionicons name="arrow-back" size={24} color="#000" />
        </TouchableOpacity>
        <Text style={styles.headerTitle}>Orders</Text>
        <View style={styles.backButton} />
      </View>
      {orders.length === 0 ? (
        <View style={styles.emptyContainer}>
          <Text style={styles.emptyText}>No orders yet</Text>
        </View>
      ) : (
        <FlatList
          data={orders}
          renderItem={renderOrder}
          keyExtractor={(item) => item.id}
          contentContainerStyle={styles.list}
        />
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
  orderCard: {
    backgroundColor: '#fff',
    borderRadius: 8,
    padding: 15,
    marginBottom: 15,
    borderWidth: 1,
    borderColor: '#eee',
  },
  orderHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: 10,
  },
  orderId: {
    fontSize: 14,
    fontWeight: '600',
  },
  orderStatus: {
    fontSize: 14,
    color: '#666',
    textTransform: 'capitalize',
  },
  orderContent: {
    flexDirection: 'row',
  },
  orderImage: {
    width: 80,
    height: 80,
    borderRadius: 8,
    marginRight: 15,
  },
  orderInfo: {
    flex: 1,
  },
  orderTitle: {
    fontSize: 16,
    fontWeight: '600',
    marginBottom: 5,
  },
  orderDate: {
    fontSize: 14,
    color: '#666',
    marginBottom: 5,
  },
  orderTotal: {
    fontSize: 18,
    fontWeight: 'bold',
  },
  centerContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  emptyContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  emptyText: {
    fontSize: 16,
    color: '#666',
  },
});

