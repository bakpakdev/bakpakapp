import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  ScrollView,
  Alert,
  Image,
} from 'react-native';
import { api } from '../services/api';
import { useNavigation, useRoute } from '@react-navigation/native';
import SuccessBanner from '../components/SuccessBanner';

export default function EditListingScreen() {
  const route = useRoute();
  const navigation = useNavigation();
  const { productId } = route.params;
  
  const [formData, setFormData] = useState({
    title: '',
    description: '',
    price: '',
    condition: '',
    size: '',
    brand: '',
    category: '',
    tags: '',
  });
  const [existingImages, setExistingImages] = useState([]);
  const [loading, setLoading] = useState(false);
  const [loadingProduct, setLoadingProduct] = useState(true);
  const [showSuccessBanner, setShowSuccessBanner] = useState(false);

  useEffect(() => {
    loadProduct();
  }, [productId]);

  const loadProduct = async () => {
    try {
      const response = await api.get(`/products/${productId}`);
      const product = response.data;
      
      setFormData({
        title: product.title || '',
        description: product.description || '',
        price: product.price?.toString() || '',
        condition: product.condition || '',
        size: product.size || '',
        brand: product.brand || '',
        category: product.category || '',
        tags: product.tags ? (Array.isArray(product.tags) ? product.tags.join(', ') : product.tags) : '',
      });
      
      setExistingImages(product.images || []);
      setLoadingProduct(false);
    } catch (error) {
      Alert.alert('Error', 'Failed to load product');
      setLoadingProduct(false);
    }
  };

  const removeExistingImage = (index) => {
    setExistingImages(existingImages.filter((_, i) => i !== index));
  };

  const handleSubmit = async () => {
    if (!formData.title || !formData.description || !formData.price || !formData.category) {
      Alert.alert('Error', 'Please fill in all required fields');
      return;
    }

    if (existingImages.length === 0) {
      Alert.alert('Error', 'Please keep at least one image');
      return;
    }

    setLoading(true);
    try {
      const updateData = {
        title: formData.title,
        description: formData.description,
        price: formData.price,
        condition: formData.condition || 'good',
        size: formData.size,
        brand: formData.brand,
        category: formData.category,
        tags: formData.tags ? JSON.stringify(formData.tags.split(',').map((t) => t.trim())) : null,
      };

      await api.put(`/products/${productId}`, updateData);

      // Show success banner
      setShowSuccessBanner(true);
      
      // Navigate back to product detail page after a short delay
      setTimeout(() => {
        navigation.goBack();
        // Refresh the product detail screen
        setTimeout(() => {
          navigation.navigate('ProductDetail', { productId });
        }, 100);
      }, 500);
    } catch (error) {
      Alert.alert('Error', error.response?.data?.message || 'Failed to update listing');
    } finally {
      setLoading(false);
    }
  };

  const handleClose = () => {
    navigation.goBack();
  };

  if (loadingProduct) {
    return (
      <View style={styles.centerContainer}>
        <Text>Loading...</Text>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <SuccessBanner
        message="Listing Updated"
        visible={showSuccessBanner}
        onHide={() => setShowSuccessBanner(false)}
      />
      <ScrollView style={styles.scrollView}>
        <View style={styles.header}>
          <TouchableOpacity onPress={handleClose} style={styles.closeButton}>
            <Text style={styles.closeButtonText}>×</Text>
          </TouchableOpacity>
          <Text style={styles.headerTitle}>Edit Listing</Text>
        </View>

        <View style={styles.section}>
          <Text style={styles.label}>Photos *</Text>
          <ScrollView horizontal showsHorizontalScrollIndicator={false} style={styles.imageContainer}>
            {existingImages.map((image, index) => (
              <View key={`existing-${index}`} style={styles.imageWrapper}>
                <Image source={{ uri: image.url }} style={styles.image} />
                <TouchableOpacity
                  style={styles.removeImageButton}
                  onPress={() => removeExistingImage(index)}
                >
                  <Text style={styles.removeImageText}>×</Text>
                </TouchableOpacity>
              </View>
            ))}
          </ScrollView>
        </View>

        <View style={styles.section}>
          <Text style={styles.label}>Title *</Text>
          <TextInput
            style={styles.input}
            value={formData.title}
            onChangeText={(text) => setFormData({ ...formData, title: text })}
            placeholder="e.g., Vintage Denim Jacket"
          />
        </View>

        <View style={styles.section}>
          <Text style={styles.label}>Description *</Text>
          <TextInput
            style={[styles.input, styles.textArea]}
            value={formData.description}
            onChangeText={(text) => setFormData({ ...formData, description: text })}
            placeholder="Describe your item..."
            multiline
            numberOfLines={4}
          />
        </View>

        <View style={styles.row}>
          <View style={[styles.section, styles.halfWidth]}>
            <Text style={styles.label}>Price ($) *</Text>
            <TextInput
              style={styles.input}
              value={formData.price}
              onChangeText={(text) => setFormData({ ...formData, price: text })}
              keyboardType="numeric"
              placeholder="0.00"
            />
          </View>

          <View style={[styles.section, styles.halfWidth]}>
            <Text style={styles.label}>Category *</Text>
            <TextInput
              style={styles.input}
              value={formData.category}
              onChangeText={(text) => setFormData({ ...formData, category: text })}
              placeholder="clothing, shoes, etc."
            />
          </View>
        </View>

        <View style={styles.row}>
          <View style={[styles.section, styles.halfWidth]}>
            <Text style={styles.label}>Condition</Text>
            <TextInput
              style={styles.input}
              value={formData.condition}
              onChangeText={(text) => setFormData({ ...formData, condition: text })}
              placeholder="new, like-new, good"
            />
          </View>

          <View style={[styles.section, styles.halfWidth]}>
            <Text style={styles.label}>Size</Text>
            <TextInput
              style={styles.input}
              value={formData.size}
              onChangeText={(text) => setFormData({ ...formData, size: text })}
              placeholder="S, M, L, etc."
            />
          </View>
        </View>

        <View style={styles.section}>
          <Text style={styles.label}>Brand</Text>
          <TextInput
            style={styles.input}
            value={formData.brand}
            onChangeText={(text) => setFormData({ ...formData, brand: text })}
            placeholder="Brand name"
          />
        </View>

        <View style={styles.section}>
          <Text style={styles.label}>Tags (comma separated)</Text>
          <TextInput
            style={styles.input}
            value={formData.tags}
            onChangeText={(text) => setFormData({ ...formData, tags: text })}
            placeholder="vintage, denim, jacket"
          />
        </View>

        <TouchableOpacity
          style={[styles.submitButton, loading && styles.buttonDisabled]}
          onPress={handleSubmit}
          disabled={loading}
        >
          <Text style={styles.submitButtonText}>
            {loading ? 'Saving...' : 'Save'}
          </Text>
        </TouchableOpacity>
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
  },
  scrollView: {
    flex: 1,
    paddingTop: 50,
  },
  centerContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  header: {
    padding: 15,
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
    flexDirection: 'row',
    alignItems: 'center',
  },
  closeButton: {
    width: 32,
    height: 32,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 10,
  },
  closeButtonText: {
    fontSize: 32,
    color: '#333',
    lineHeight: 32,
  },
  headerTitle: {
    fontSize: 28,
    fontWeight: 'bold',
    flex: 1,
  },
  section: {
    padding: 15,
  },
  label: {
    fontSize: 14,
    fontWeight: '600',
    marginBottom: 8,
    color: '#333',
  },
  input: {
    borderWidth: 1,
    borderColor: '#ddd',
    borderRadius: 8,
    padding: 12,
    fontSize: 16,
  },
  textArea: {
    height: 100,
    textAlignVertical: 'top',
  },
  row: {
    flexDirection: 'row',
  },
  halfWidth: {
    width: '50%',
  },
  imageContainer: {
    flexDirection: 'row',
  },
  imageWrapper: {
    marginRight: 10,
    position: 'relative',
  },
  image: {
    width: 100,
    height: 100,
    borderRadius: 8,
  },
  removeImageButton: {
    position: 'absolute',
    top: -5,
    right: -5,
    backgroundColor: '#ff4444',
    borderRadius: 15,
    width: 30,
    height: 30,
    justifyContent: 'center',
    alignItems: 'center',
  },
  removeImageText: {
    color: '#fff',
    fontSize: 20,
    fontWeight: 'bold',
  },
  addImageButton: {
    width: 100,
    height: 100,
    borderWidth: 2,
    borderColor: '#ddd',
    borderStyle: 'dashed',
    borderRadius: 8,
    justifyContent: 'center',
    alignItems: 'center',
  },
  addImageText: {
    color: '#666',
    fontSize: 14,
  },
  submitButton: {
    backgroundColor: '#154733',
    padding: 15,
    margin: 15,
    borderRadius: 8,
    alignItems: 'center',
  },
  buttonDisabled: {
    opacity: 0.6,
  },
  submitButtonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
});

