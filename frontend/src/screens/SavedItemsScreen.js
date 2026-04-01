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
import { useNavigation, useFocusEffect } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import { api } from '../services/api';

const { width } = Dimensions.get('window');
const itemWidth = (width - 30) / 2;

export default function SavedItemsScreen() {
  const [savedItems, setSavedItems] = useState([]);
  const [loading, setLoading] = useState(true);
  const navigation = useNavigation();

  useFocusEffect(
    React.useCallback(() => {
      loadSavedItems();
    }, [])
  );

  const loadSavedItems = async () => {
    try {
      const response = await api.get('/social/saved');
      setSavedItems(response.data);
    } catch (error) {
      console.error('Error loading saved items:', error);
    } finally {
      setLoading(false);
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
        <View style={styles.productInfo}>
          <Text style={styles.productPrice}>${item.price}</Text>
          <Text style={styles.productTitle} numberOfLines={1}>
            {item.title}
          </Text>
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
        <Text style={styles.headerTitle}>Saved Items</Text>
        <View style={styles.backButton} />
      </View>
      {savedItems.length === 0 ? (
        <View style={styles.emptyContainer}>
          <Text style={styles.emptyText}>No saved items yet</Text>
        </View>
      ) : (
        <FlatList
          data={savedItems}
          renderItem={renderProduct}
          keyExtractor={(item) => item.id}
          numColumns={2}
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
    padding: 10,
  },
  productCard: {
    width: itemWidth,
    margin: 5,
    backgroundColor: '#fff',
    borderRadius: 8,
    overflow: 'hidden',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 3,
  },
  productImage: {
    width: '100%',
    height: itemWidth,
    backgroundColor: '#f0f0f0',
  },
  productInfo: {
    padding: 10,
  },
  productPrice: {
    fontSize: 16,
    fontWeight: 'bold',
    marginBottom: 4,
  },
  productTitle: {
    fontSize: 14,
    color: '#333',
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

