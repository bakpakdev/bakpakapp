import React, { useState, useRef } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  ScrollView,
  Alert,
  Image,
  Platform,
  Animated,
  Dimensions,
} from 'react-native';
import * as ImagePicker from 'expo-image-picker';
import { Ionicons } from '@expo/vector-icons';
import { api } from '../services/api';
import { useNavigation } from '@react-navigation/native';
import SuccessBanner from '../components/SuccessBanner';
import { LinearGradient } from 'expo-linear-gradient';

const { width } = Dimensions.get('window');
const PHOTO_SIZE = (width - 64) / 3; // 3 columns with padding

const GENDER_TYPES = [
  { id: 'mens', name: "Men's" },
  { id: 'womens', name: "Women's" },
  { id: 'kids', name: "Kids" },
];

const CLOTHING_CATEGORIES = [
  { id: 'tops', name: 'Tops & Shirts' },
  { id: 'bottoms', name: 'Bottoms' },
  { id: 'shoes', name: 'Shoes' },
  { id: 'accessories', name: 'Accessories' },
];

const TOP_TYPES = [
  { id: 't-shirts', name: 'T-Shirts' },
  { id: 'hoodies', name: 'Hoodies' },
  { id: 'sweatshirts', name: 'Sweatshirts' },
  { id: 'sweaters', name: 'Sweaters' },
  { id: 'shirts', name: 'Shirts' },
  { id: 'polos', name: 'Polos' },
  { id: 'blouses', name: 'Blouses' },
  { id: 'croptops', name: 'Crop Tops' },
  { id: 'tanktops', name: 'Tank Tops' },
];

const BOTTOM_TYPES = [
  { id: 'jeans', name: 'Jeans' },
  { id: 'sweatpants', name: 'Sweatpants' },
  { id: 'pants', name: 'Pants' },
  { id: 'shorts', name: 'Shorts' },
  { id: 'leggings', name: 'Leggings' },
  { id: 'skirts', name: 'Skirts' },
];

const SIZE_OPTIONS = {
  tops: [
    { id: 'xs', name: 'XS' },
    { id: 's', name: 'S' },
    { id: 'm', name: 'M' },
    { id: 'l', name: 'L' },
    { id: 'xl', name: 'XL' },
    { id: 'other', name: 'Other' },
  ],
  bottoms: {
    jeans: [
      { id: '28x30', name: '28x30' },
      { id: '28x32', name: '28x32' },
      { id: '30x30', name: '30x30' },
      { id: '30x32', name: '30x32' },
      { id: '32x30', name: '32x30' },
      { id: '32x32', name: '32x32' },
      { id: '32x34', name: '32x34' },
      { id: '34x30', name: '34x30' },
      { id: '34x32', name: '34x32' },
      { id: '34x34', name: '34x34' },
      { id: '36x30', name: '36x30' },
      { id: '36x32', name: '36x32' },
      { id: '36x34', name: '36x34' },
      { id: '38x30', name: '38x30' },
      { id: '38x32', name: '38x32' },
      { id: '38x34', name: '38x34' },
      { id: 'other', name: 'Other' },
    ],
    sweatpants: [
      { id: 'xs', name: 'XS' },
      { id: 's', name: 'S' },
      { id: 'm', name: 'M' },
      { id: 'l', name: 'L' },
      { id: 'xl', name: 'XL' },
      { id: 'other', name: 'Other' },
    ],
    pants: [
      { id: 'xs', name: 'XS' },
      { id: 's', name: 'S' },
      { id: 'm', name: 'M' },
      { id: 'l', name: 'L' },
      { id: 'xl', name: 'XL' },
      { id: 'other', name: 'Other' },
    ],
    shorts: [
      { id: 'xs', name: 'XS' },
      { id: 's', name: 'S' },
      { id: 'm', name: 'M' },
      { id: 'l', name: 'L' },
      { id: 'xl', name: 'XL' },
      { id: 'other', name: 'Other' },
    ],
    leggings: [
      { id: 'xs', name: 'XS' },
      { id: 's', name: 'S' },
      { id: 'm', name: 'M' },
      { id: 'l', name: 'L' },
      { id: 'xl', name: 'XL' },
      { id: 'other', name: 'Other' },
    ],
    skirts: [
      { id: 'xs', name: 'XS' },
      { id: 's', name: 'S' },
      { id: 'm', name: 'M' },
      { id: 'l', name: 'L' },
      { id: 'xl', name: 'XL' },
      { id: 'other', name: 'Other' },
    ],
  },
  shoes: [
    { id: '3', name: 'US 3' },
    { id: '3.5', name: 'US 3.5' },
    { id: '4', name: 'US 4' },
    { id: '4.5', name: 'US 4.5' },
    { id: '5', name: 'US 5' },
    { id: '5.5', name: 'US 5.5' },
    { id: '6', name: 'US 6' },
    { id: '6.5', name: 'US 6.5' },
    { id: '7', name: 'US 7' },
    { id: '7.5', name: 'US 7.5' },
    { id: '8', name: 'US 8' },
    { id: '8.5', name: 'US 8.5' },
    { id: '9', name: 'US 9' },
    { id: '9.5', name: 'US 9.5' },
    { id: '10', name: 'US 10' },
    { id: '10.5', name: 'US 10.5' },
    { id: '11', name: 'US 11' },
    { id: '11.5', name: 'US 11.5' },
    { id: '12', name: 'US 12' },
    { id: '12.5', name: 'US 12.5' },
    { id: '13', name: 'US 13' },
    { id: '13.5', name: 'US 13.5' },
    { id: '14', name: 'US 14' },
    { id: '14.5', name: 'US 14.5' },
    { id: '15', name: 'US 15' },
    { id: 'other', name: 'Other' },
  ],
  accessories: [
    { id: 'one-size', name: 'One Size' },
    { id: 'other', name: 'Other' },
  ],
};

const CONDITIONS = [
  { id: 'new', name: 'Brand New', desc: 'Never used, with tags' },
  { id: 'like-new', name: 'Like New', desc: 'Gently used, excellent condition' },
  { id: 'good', name: 'Good', desc: 'Used with minor wear' },
  { id: 'fair', name: 'Fair', desc: 'Used with noticeable wear' },
];

const DORM_HALLS = [
  { id: 'bean', name: 'Bean Hall' },
  { id: 'barnhart', name: 'Barnhart Hall' },
  { id: 'carson', name: 'Carson Hall' },
  { id: 'earl', name: 'Earl Hall' },
  { id: 'global-scholars', name: 'Global Scholars Hall' },
  { id: 'kalapuya-ilihi', name: 'Kalapuya Ilihi' },
  { id: 'llc-north', name: 'LLC North' },
  { id: 'llc-south', name: 'LLC South' },
  { id: 'riley', name: 'Riley Hall' },
  { id: 'unthank', name: 'Unthank Hall' },
  { id: 'yasui', name: 'Yasui Hall' },
  { id: 'off-campus', name: 'Off-Campus' },
];

export default function CreateListingScreen() {
  const [photos, setPhotos] = useState([]);
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [price, setPrice] = useState('');
  const [category, setCategory] = useState('');
  const [genderType, setGenderType] = useState('');
  const [topType, setTopType] = useState('');
  const [bottomType, setBottomType] = useState('');
  const [size, setSize] = useState('');
  const [condition, setCondition] = useState('');
  const [dormHall, setDormHall] = useState('');
  const [showCategoryPicker, setShowCategoryPicker] = useState(false);
  const [categoryPickerStep, setCategoryPickerStep] = useState('gender'); // 'gender', 'clothing', 'topType', or 'bottomType'
  const [showSizePicker, setShowSizePicker] = useState(false);
  const [showConditionPicker, setShowConditionPicker] = useState(false);
  const [showDormHallPicker, setShowDormHallPicker] = useState(false);
  const [loading, setLoading] = useState(false);
  const [showSuccessBanner, setShowSuccessBanner] = useState(false);
  
  const navigation = useNavigation();
  const categoryPickerHeight = useRef(new Animated.Value(0)).current;
  const categoryPickerOpacity = useRef(new Animated.Value(0)).current;
  const sizePickerHeight = useRef(new Animated.Value(0)).current;
  const sizePickerOpacity = useRef(new Animated.Value(0)).current;
  const conditionPickerHeight = useRef(new Animated.Value(0)).current;
  const conditionPickerOpacity = useRef(new Animated.Value(0)).current;
  const dormHallPickerHeight = useRef(new Animated.Value(0)).current;
  const dormHallPickerOpacity = useRef(new Animated.Value(0)).current;

  const pickImage = async () => {
    if (photos.length >= 5) {
      Alert.alert('Limit reached', 'You can only upload up to 5 photos');
      return;
    }

    const { status } = await ImagePicker.requestMediaLibraryPermissionsAsync();
    if (status !== 'granted') {
      Alert.alert('Permission needed', 'Please grant camera roll permissions');
      return;
    }

    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ImagePicker.MediaTypeOptions.Images,
      allowsEditing: true,
      aspect: [4, 3],
      quality: 0.8,
      allowsMultipleSelection: Platform.OS !== 'web',
    });

    if (!result.canceled && result.assets) {
      const remainingSlots = 5 - photos.length;
      const newPhotos = result.assets.slice(0, remainingSlots).map((asset, idx) => ({
        id: `photo-${Date.now()}-${idx}`,
        uri: asset.uri,
      }));
      setPhotos([...photos, ...newPhotos]);
    }
  };

  const removePhoto = (id) => {
    setPhotos(photos.filter(p => p.id !== id));
  };

  const toggleCategoryPicker = () => {
    const toValue = showCategoryPicker ? 0 : 1;
    if (!showCategoryPicker) {
      // Reset to appropriate step when opening
      if (category === 'bottoms' && bottomType) {
        setCategoryPickerStep('bottomType');
      } else if (category === 'tops' && topType) {
        setCategoryPickerStep('topType');
      } else if (category && CLOTHING_CATEGORIES.find(c => c.id === category)) {
        setCategoryPickerStep('clothing');
      } else {
        setCategoryPickerStep('gender');
      }
    } else {
      // When closing, if no category is selected, reset gender
      if (!category) {
        setGenderType('');
        setCategoryPickerStep('gender');
      }
    }
    setShowCategoryPicker(!showCategoryPicker);
    
    Animated.parallel([
      Animated.timing(categoryPickerHeight, {
        toValue,
        duration: 200,
        useNativeDriver: Platform.OS !== 'web',
      }),
      Animated.timing(categoryPickerOpacity, {
        toValue,
        duration: 200,
        useNativeDriver: Platform.OS !== 'web',
      }),
    ]).start();
  };

  const toggleConditionPicker = () => {
    const toValue = showConditionPicker ? 0 : 1;
    setShowConditionPicker(!showConditionPicker);
    
    Animated.parallel([
      Animated.timing(conditionPickerHeight, {
        toValue,
        duration: 200,
        useNativeDriver: Platform.OS !== 'web',
      }),
      Animated.timing(conditionPickerOpacity, {
        toValue,
        duration: 200,
        useNativeDriver: Platform.OS !== 'web',
      }),
    ]).start();
  };

  const toggleDormHallPicker = () => {
    const toValue = showDormHallPicker ? 0 : 1;
    setShowDormHallPicker(!showDormHallPicker);
    
    Animated.parallel([
      Animated.timing(dormHallPickerHeight, {
        toValue,
        duration: 200,
        useNativeDriver: Platform.OS !== 'web',
      }),
      Animated.timing(dormHallPickerOpacity, {
        toValue,
        duration: 200,
        useNativeDriver: Platform.OS !== 'web',
      }),
    ]).start();
  };

  const categoryPickerMaxHeight = categoryPickerHeight.interpolate({
    inputRange: [0, 1],
    outputRange: [0, Math.max(
      GENDER_TYPES.length * 60,
      (CLOTHING_CATEGORIES.length + 1) * 60,
      (BOTTOM_TYPES.length + 1) * 60,
      (TOP_TYPES.length + 1) * 60
    )],
  });

  const toggleSizePicker = () => {
    const toValue = showSizePicker ? 0 : 1;
    setShowSizePicker(!showSizePicker);
    
    Animated.parallel([
      Animated.timing(sizePickerHeight, {
        toValue,
        duration: 200,
        useNativeDriver: Platform.OS !== 'web',
      }),
      Animated.timing(sizePickerOpacity, {
        toValue,
        duration: 200,
        useNativeDriver: Platform.OS !== 'web',
      }),
    ]).start();
  };

  const getSizeOptions = () => {
    if (!category) return [];
    if (category === 'bottoms' && bottomType) {
      return SIZE_OPTIONS.bottoms[bottomType] || [];
    }
    return SIZE_OPTIONS[category] || [];
  };

  const sizePickerMaxHeight = sizePickerHeight.interpolate({
    inputRange: [0, 1],
    outputRange: [0, getSizeOptions().length * 60],
  });

  const conditionPickerMaxHeight = conditionPickerHeight.interpolate({
    inputRange: [0, 1],
    outputRange: [0, CONDITIONS.length * 70],
  });

  const dormHallPickerMaxHeight = dormHallPickerHeight.interpolate({
    inputRange: [0, 1],
    outputRange: [0, DORM_HALLS.length * 60],
  });

  const handleSubmit = async () => {
    if (!title || !price || !category || !condition || photos.length === 0) {
      Alert.alert('Error', 'Please fill in all required fields and add at least one photo');
      return;
    }

    setLoading(true);
    try {
      const formDataToSend = new FormData();
      formDataToSend.append('title', title);
      formDataToSend.append('description', description || '');
      formDataToSend.append('price', price);
      formDataToSend.append('condition', condition);
      formDataToSend.append('category', category);
      if (genderType) {
        formDataToSend.append('genderType', genderType);
      }
      if (category === 'tops' && topType) {
        formDataToSend.append('topType', topType);
      }
      if (category === 'bottoms' && bottomType) {
        formDataToSend.append('bottomType', bottomType);
      }
      if (size) {
        formDataToSend.append('size', size);
      }
      if (dormHall) {
        formDataToSend.append('dormHall', dormHall);
      }
      formDataToSend.append('tags', JSON.stringify([]));

      // Handle image uploads
      if (Platform.OS === 'web') {
        for (let index = 0; index < photos.length; index++) {
          const photo = photos[index];
          const response = await fetch(photo.uri);
          const blob = await response.blob();
          formDataToSend.append('images', blob, `image${index}.jpg`);
        }
      } else {
        photos.forEach((photo, index) => {
          formDataToSend.append('images', {
            uri: photo.uri,
            type: 'image/jpeg',
            name: `image${index}.jpg`,
          });
        });
      }

      const response = await api.post('/products', formDataToSend, {
        headers: {
          'Content-Type': 'multipart/form-data',
        },
      });

      const createdProduct = response.data;
      
      if (!createdProduct || !createdProduct.id) {
        Alert.alert('Error', 'Product was created but ID is missing');
        return;
      }
      
      setShowSuccessBanner(true);
      
      setTimeout(() => {
        navigation.navigate('ProductDetail', { productId: createdProduct.id });
      }, 500);
    } catch (error) {
      Alert.alert('Error', error.response?.data?.message || 'Failed to create listing');
    } finally {
      setLoading(false);
    }
  };

  const isFormValid = title && price && category && condition && photos.length > 0;

  return (
    <View style={styles.container}>
      <SuccessBanner
        message="Listing Posted"
        visible={showSuccessBanner}
        onClose={() => setShowSuccessBanner(false)}
      />
      
      {/* Header */}
      <View style={styles.header}>
        <TouchableOpacity onPress={() => navigation.goBack()} style={styles.backButton}>
          <Ionicons name="arrow-back" size={20} color="#374151" />
        </TouchableOpacity>
        <Text style={styles.headerTitle}>Create Listing</Text>
        <TouchableOpacity
          onPress={handleSubmit}
          disabled={!isFormValid || loading}
          style={[styles.postButton, !isFormValid && styles.postButtonDisabled]}
        >
          <Text style={[styles.postButtonText, !isFormValid && styles.postButtonTextDisabled]}>
            {loading ? 'Posting...' : 'Post'}
          </Text>
        </TouchableOpacity>
      </View>

      <ScrollView
        style={styles.scrollView}
        contentContainerStyle={styles.scrollContent}
        showsVerticalScrollIndicator={false}
      >
        {/* Photo Upload Section */}
        <View style={styles.section}>
          <View style={styles.sectionHeader}>
            <Ionicons name="camera-outline" size={16} color="#111827" />
            <View style={styles.sectionTitleRow}>
              <Text style={styles.sectionTitle}>Photos</Text>
              <Text style={styles.sectionSubtitle}>({photos.length}/5)</Text>
            </View>
          </View>
          <View style={styles.photosGrid}>
            {photos.map((photo, idx) => (
              <View key={photo.id} style={styles.photoWrapper}>
                <Image source={{ uri: photo.uri }} style={styles.photoPreview} />
                {idx === 0 && (
                  <View style={styles.coverBadge}>
                    <Text style={styles.coverBadgeText}>Cover</Text>
                  </View>
                )}
                <TouchableOpacity
                  style={styles.removePhotoButton}
                  onPress={() => removePhoto(photo.id)}
                >
                  <Ionicons name="close" size={16} color="#fff" />
                </TouchableOpacity>
              </View>
            ))}
            {photos.length < 5 && (
              <TouchableOpacity
                style={styles.photoUploadBox}
                onPress={pickImage}
                activeOpacity={0.7}
              >
                <View style={styles.photoUploadIcon}>
                  <Ionicons name="camera-outline" size={24} color="#4b5563" />
                </View>
                <Text style={styles.photoUploadText}>Add Photo</Text>
                {photos.length === 0 && (
                  <View style={styles.coverBadge}>
                    <Text style={styles.coverBadgeText}>Cover</Text>
                  </View>
                )}
              </TouchableOpacity>
            )}
          </View>
          <Text style={styles.photoHint}>
            First photo will be your cover image
          </Text>
        </View>

        {/* Title Input */}
        <View style={styles.section}>
          <View style={styles.sectionHeader}>
            <Ionicons name="pricetag-outline" size={16} color="#111827" />
            <Text style={styles.sectionTitle}>Title</Text>
          </View>
          <TextInput
            style={styles.input}
            placeholder="e.g., Vintage Oversized Hoodie"
            placeholderTextColor="#9ca3af"
            value={title}
            onChangeText={setTitle}
            maxLength={80}
          />
          <Text style={styles.charCount}>{title.length}/80 characters</Text>
        </View>

        {/* Category Picker */}
        <View style={styles.section}>
          <Text style={styles.label}>Category</Text>
          <TouchableOpacity
            style={styles.pickerButton}
            onPress={toggleCategoryPicker}
            activeOpacity={0.7}
          >
            <Text style={[styles.pickerButtonText, !category && styles.pickerButtonTextPlaceholder]}>
              {category
                ? category === 'bottoms' && bottomType
                  ? `${genderType ? GENDER_TYPES.find(g => g.id === genderType)?.name + ' - ' : ''}${CLOTHING_CATEGORIES.find(c => c.id === category)?.name} - ${BOTTOM_TYPES.find(b => b.id === bottomType)?.name}`
                  : category === 'tops' && topType
                  ? `${genderType ? GENDER_TYPES.find(g => g.id === genderType)?.name + ' - ' : ''}${CLOTHING_CATEGORIES.find(c => c.id === category)?.name} - ${TOP_TYPES.find(t => t.id === topType)?.name}`
                  : genderType && CLOTHING_CATEGORIES.find(c => c.id === category)
                  ? `${GENDER_TYPES.find(g => g.id === genderType)?.name} - ${CLOTHING_CATEGORIES.find(c => c.id === category)?.name}`
                  : CLOTHING_CATEGORIES.find(c => c.id === category)?.name
                : 'Select a category'}
            </Text>
            <Ionicons
              name="chevron-down"
              size={16}
              color="#9ca3af"
              style={[
                styles.chevronIcon,
                showCategoryPicker && styles.chevronIconRotated,
              ]}
            />
          </TouchableOpacity>
          
          {showCategoryPicker && (
            <Animated.View
              style={[
                styles.pickerDropdown,
                {
                  maxHeight: categoryPickerMaxHeight,
                  opacity: categoryPickerOpacity,
                },
              ]}
            >
              <View style={styles.pickerDropdownContent}>
                {categoryPickerStep === 'gender' ? (
                  /* Gender Options */
                  GENDER_TYPES.map((gender) => (
                    <TouchableOpacity
                      key={gender.id}
                      style={[
                        styles.pickerOption,
                        genderType === gender.id && styles.pickerOptionActive,
                      ]}
                      onPress={() => {
                        setGenderType(gender.id);
                        setCategoryPickerStep('clothing');
                      }}
                      activeOpacity={0.7}
                    >
                      <Text style={styles.pickerOptionText}>{gender.name}</Text>
                      {genderType === gender.id && (
                        <View style={styles.pickerOptionIndicator} />
                      )}
                    </TouchableOpacity>
                  ))
                ) : categoryPickerStep === 'topType' ? (
                  /* Top Types (after tops selected) */
                  <>
                    <TouchableOpacity
                      style={styles.pickerOption}
                      onPress={() => {
                        setCategoryPickerStep('clothing');
                        setCategory('');
                        setTopType('');
                      }}
                      activeOpacity={0.7}
                    >
                      <Ionicons name="arrow-back" size={16} color="#6b7280" />
                      <Text style={[styles.pickerOptionText, { marginLeft: 8 }]}>Back</Text>
                    </TouchableOpacity>
                    {TOP_TYPES.map((top) => (
                      <TouchableOpacity
                        key={top.id}
                        style={[
                          styles.pickerOption,
                          topType === top.id && styles.pickerOptionActive,
                        ]}
                        onPress={() => {
                          setTopType(top.id);
                          setSize(''); // Reset size when top type changes
                          toggleCategoryPicker();
                        }}
                        activeOpacity={0.7}
                      >
                        <Text style={styles.pickerOptionText}>{top.name}</Text>
                        {topType === top.id && (
                          <View style={styles.pickerOptionIndicator} />
                        )}
                      </TouchableOpacity>
                    ))}
                  </>
                ) : categoryPickerStep === 'bottomType' ? (
                  /* Bottom Types (after bottoms selected) */
                  <>
                    <TouchableOpacity
                      style={styles.pickerOption}
                      onPress={() => {
                        setCategoryPickerStep('clothing');
                        setCategory('');
                        setBottomType('');
                      }}
                      activeOpacity={0.7}
                    >
                      <Ionicons name="arrow-back" size={16} color="#6b7280" />
                      <Text style={[styles.pickerOptionText, { marginLeft: 8 }]}>Back</Text>
                    </TouchableOpacity>
                    {BOTTOM_TYPES.map((bottom) => (
                      <TouchableOpacity
                        key={bottom.id}
                        style={[
                          styles.pickerOption,
                          bottomType === bottom.id && styles.pickerOptionActive,
                        ]}
                        onPress={() => {
                          setBottomType(bottom.id);
                          setSize(''); // Reset size when bottom type changes
                          toggleCategoryPicker();
                        }}
                        activeOpacity={0.7}
                      >
                        <Text style={styles.pickerOptionText}>{bottom.name}</Text>
                        {bottomType === bottom.id && (
                          <View style={styles.pickerOptionIndicator} />
                        )}
                      </TouchableOpacity>
                    ))}
                  </>
                ) : (
                  /* Clothing Categories (after gender selected) */
                  <>
                    <TouchableOpacity
                      style={styles.pickerOption}
                      onPress={() => {
                        setCategoryPickerStep('gender');
                        setGenderType('');
                      }}
                      activeOpacity={0.7}
                    >
                      <Ionicons name="arrow-back" size={16} color="#6b7280" />
                      <Text style={[styles.pickerOptionText, { marginLeft: 8 }]}>Back</Text>
                    </TouchableOpacity>
                    {CLOTHING_CATEGORIES.map((cat) => (
                      <TouchableOpacity
                        key={cat.id}
                        style={[
                          styles.pickerOption,
                          category === cat.id && styles.pickerOptionActive,
                        ]}
                        onPress={() => {
                          if (cat.id === 'bottoms') {
                            setCategory(cat.id);
                            setCategoryPickerStep('bottomType');
                          } else if (cat.id === 'tops') {
                            setCategory(cat.id);
                            setCategoryPickerStep('topType');
                          } else {
                            setCategory(cat.id);
                            setSize(''); // Reset size when category changes
                            setTopType(''); // Reset top type when category changes
                            setBottomType(''); // Reset bottom type when category changes
                            toggleCategoryPicker();
                          }
                        }}
                        activeOpacity={0.7}
                      >
                        <Text style={styles.pickerOptionText}>{cat.name}</Text>
                        {category === cat.id && (
                          <View style={styles.pickerOptionIndicator} />
                        )}
                      </TouchableOpacity>
                    ))}
                  </>
                )}
              </View>
            </Animated.View>
          )}
        </View>

        {/* Size Picker */}
        {category && (category === 'bottoms' ? (bottomType && getSizeOptions().length > 0) : SIZE_OPTIONS[category]) && (
          <View style={styles.section}>
            <Text style={styles.label}>Size</Text>
            <TouchableOpacity
              style={styles.pickerButton}
              onPress={toggleSizePicker}
              activeOpacity={0.7}
            >
              <Text style={[styles.pickerButtonText, !size && styles.pickerButtonTextPlaceholder]}>
                {size
                  ? getSizeOptions().find(s => s.id === size)?.name
                  : 'Select size'}
              </Text>
              <Ionicons
                name="chevron-down"
                size={16}
                color="#9ca3af"
                style={[
                  styles.chevronIcon,
                  showSizePicker && styles.chevronIconRotated,
                ]}
              />
            </TouchableOpacity>
            
            {showSizePicker && (
              <Animated.View
                style={[
                  styles.pickerDropdown,
                  {
                    maxHeight: sizePickerMaxHeight,
                    opacity: sizePickerOpacity,
                  },
                ]}
              >
                <View style={styles.pickerDropdownContent}>
                  {getSizeOptions().map((sizeOption) => (
                    <TouchableOpacity
                      key={sizeOption.id}
                      style={[
                        styles.pickerOption,
                        size === sizeOption.id && styles.pickerOptionActive,
                      ]}
                      onPress={() => {
                        setSize(sizeOption.id);
                        toggleSizePicker();
                      }}
                      activeOpacity={0.7}
                    >
                      <Text style={styles.pickerOptionText}>{sizeOption.name}</Text>
                      {size === sizeOption.id && (
                        <View style={styles.pickerOptionIndicator} />
                      )}
                    </TouchableOpacity>
                  ))}
                </View>
              </Animated.View>
            )}
          </View>
        )}

        {/* Condition Picker */}
        <View style={styles.section}>
          <Text style={styles.label}>Condition</Text>
          <TouchableOpacity
            style={styles.pickerButton}
            onPress={toggleConditionPicker}
            activeOpacity={0.7}
          >
            <Text style={[styles.pickerButtonText, !condition && styles.pickerButtonTextPlaceholder]}>
              {condition
                ? CONDITIONS.find(c => c.id === condition)?.name
                : 'Select condition'}
            </Text>
            <Ionicons
              name="chevron-down"
              size={16}
              color="#9ca3af"
              style={[
                styles.chevronIcon,
                showConditionPicker && styles.chevronIconRotated,
              ]}
            />
          </TouchableOpacity>
          
          {showConditionPicker && (
            <Animated.View
              style={[
                styles.pickerDropdown,
                {
                  maxHeight: conditionPickerMaxHeight,
                  opacity: conditionPickerOpacity,
                },
              ]}
            >
              <View style={styles.pickerDropdownContent}>
                {CONDITIONS.map((cond) => (
                  <TouchableOpacity
                    key={cond.id}
                    style={[
                      styles.pickerOption,
                      styles.pickerOptionCondition,
                      condition === cond.id && styles.pickerOptionActive,
                    ]}
                    onPress={() => {
                      setCondition(cond.id);
                      toggleConditionPicker();
                    }}
                    activeOpacity={0.7}
                  >
                    <View style={styles.pickerOptionConditionContent}>
                      <Text style={styles.pickerOptionText}>{cond.name}</Text>
                      <Text style={styles.pickerOptionDesc}>{cond.desc}</Text>
                    </View>
                    {condition === cond.id && (
                      <View style={styles.pickerOptionIndicator} />
                    )}
                  </TouchableOpacity>
                ))}
              </View>
            </Animated.View>
          )}
        </View>

        {/* Dorm Hall Picker */}
        <View style={styles.section}>
          <Text style={styles.label}>Dorm Hall / Living Residence</Text>
          <TouchableOpacity
            style={styles.pickerButton}
            onPress={toggleDormHallPicker}
            activeOpacity={0.7}
          >
            <Text style={[styles.pickerButtonText, !dormHall && styles.pickerButtonTextPlaceholder]}>
              {dormHall
                ? DORM_HALLS.find(d => d.id === dormHall)?.name
                : 'Select dorm hall'}
            </Text>
            <Ionicons
              name="chevron-down"
              size={16}
              color="#9ca3af"
              style={[
                styles.chevronIcon,
                showDormHallPicker && styles.chevronIconRotated,
              ]}
            />
          </TouchableOpacity>
          
          {showDormHallPicker && (
            <Animated.View
              style={[
                styles.pickerDropdown,
                {
                  maxHeight: dormHallPickerMaxHeight,
                  opacity: dormHallPickerOpacity,
                },
              ]}
            >
              <View style={styles.pickerDropdownContent}>
                {DORM_HALLS.map((dorm) => (
                  <TouchableOpacity
                    key={dorm.id}
                    style={[
                      styles.pickerOption,
                      dormHall === dorm.id && styles.pickerOptionActive,
                    ]}
                    onPress={() => {
                      setDormHall(dorm.id);
                      toggleDormHallPicker();
                    }}
                    activeOpacity={0.7}
                  >
                    <Text style={styles.pickerOptionText}>{dorm.name}</Text>
                    {dormHall === dorm.id && (
                      <View style={styles.pickerOptionIndicator} />
                    )}
                  </TouchableOpacity>
                ))}
              </View>
            </Animated.View>
          )}
        </View>

        {/* Price Input */}
        <View style={styles.section}>
          <View style={styles.sectionHeader}>
            <Ionicons name="cash-outline" size={16} color="#111827" />
            <Text style={styles.sectionTitle}>Price</Text>
          </View>
          <View style={styles.priceInputContainer}>
            <Text style={styles.priceSymbol}>$</Text>
            <TextInput
              style={styles.priceInput}
              placeholder="0"
              placeholderTextColor="#9ca3af"
              value={price}
              onChangeText={setPrice}
              keyboardType="numeric"
            />
          </View>
          <Text style={styles.priceHint}>Set a fair price for your item</Text>
        </View>

        {/* Description Input */}
        <View style={styles.section}>
          <View style={styles.sectionHeader}>
            <Ionicons name="document-text-outline" size={16} color="#111827" />
            <View style={styles.sectionTitleRow}>
              <Text style={styles.sectionTitle}>Description</Text>
              <Text style={styles.optionalLabel}>(Optional)</Text>
            </View>
          </View>
          <TextInput
            style={styles.textArea}
            placeholder="Add details about size, brand, condition, or why you're selling..."
            placeholderTextColor="#9ca3af"
            value={description}
            onChangeText={setDescription}
            multiline
            numberOfLines={4}
            maxLength={500}
            textAlignVertical="top"
          />
          <Text style={styles.charCount}>{description.length}/500 characters</Text>
        </View>

        {/* Tips Box */}
        <View style={styles.tipsContainer}>
          <LinearGradient
            colors={['#e6f2ed', '#f0f9f4']}
            start={{ x: 0, y: 0 }}
            end={{ x: 1, y: 1 }}
            style={styles.tipsGradient}
          >
            <View style={styles.tipsContent}>
              <View style={styles.tipsIconContainer}>
                <Ionicons name="bulb-outline" size={16} color="#154733" />
              </View>
              <View style={styles.tipsTextContainer}>
                <Text style={styles.tipsTitle}>Quick Tips</Text>
                <View style={styles.tipsList}>
                  <Text style={styles.tipsItem}>• Use clear, well-lit photos</Text>
                  <Text style={styles.tipsItem}>• Be honest about condition</Text>
                  <Text style={styles.tipsItem}>• Include measurements for clothing</Text>
                  <Text style={styles.tipsItem}>• Check similar listings for pricing</Text>
                </View>
              </View>
            </View>
          </LinearGradient>
        </View>
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#ffffff',
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: '#f3f4f6',
    backgroundColor: '#ffffff',
  },
  backButton: {
    padding: 4,
  },
  headerTitle: {
    fontSize: 18,
    fontWeight: 'bold',
    color: '#111827',
  },
  postButton: {
    paddingHorizontal: 16,
    paddingVertical: 6,
    borderRadius: 20,
    backgroundColor: '#154733',
  },
  postButtonDisabled: {
    backgroundColor: '#f3f4f6',
  },
  postButtonText: {
    fontSize: 14,
    fontWeight: 'bold',
    color: '#ffffff',
  },
  postButtonTextDisabled: {
    color: '#9ca3af',
  },
  scrollView: {
    flex: 1,
  },
  scrollContent: {
    padding: 16,
    paddingBottom: 80,
  },
  section: {
    marginBottom: 24,
  },
  sectionHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 12,
    gap: 8,
  },
  sectionTitleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  sectionTitle: {
    fontSize: 14,
    fontWeight: 'bold',
    color: '#111827',
  },
  sectionSubtitle: {
    fontSize: 14,
    fontWeight: 'normal',
    color: '#9ca3af',
  },
  optionalLabel: {
    fontSize: 14,
    fontWeight: 'normal',
    color: '#9ca3af',
  },
  photosGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 12,
    marginBottom: 8,
  },
  photoWrapper: {
    width: PHOTO_SIZE,
    height: PHOTO_SIZE,
    borderRadius: 16,
    overflow: 'hidden',
    backgroundColor: '#f3f4f6',
  },
  photoPreview: {
    width: '100%',
    height: '100%',
  },
  photoUploadBox: {
    width: PHOTO_SIZE,
    height: PHOTO_SIZE,
    borderRadius: 16,
    borderWidth: 2,
    borderStyle: 'dashed',
    borderColor: '#d1d5db',
    backgroundColor: '#f9fafb',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
  },
  photoUploadIcon: {
    width: 48,
    height: 48,
    borderRadius: 24,
    backgroundColor: '#ffffff',
    alignItems: 'center',
    justifyContent: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.1,
    shadowRadius: 2,
    elevation: 2,
  },
  photoUploadText: {
    fontSize: 12,
    fontWeight: '500',
    color: '#6b7280',
  },
  coverBadge: {
    position: 'absolute',
    top: 8,
    left: 8,
    backgroundColor: '#154733',
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 12,
  },
  coverBadgeText: {
    fontSize: 10,
    fontWeight: 'bold',
    color: '#ffffff',
  },
  removePhotoButton: {
    position: 'absolute',
    top: 8,
    right: 8,
    width: 24,
    height: 24,
    borderRadius: 12,
    backgroundColor: 'rgba(0, 0, 0, 0.7)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  photoHint: {
    fontSize: 12,
    color: '#6b7280',
    marginLeft: 4,
  },
  input: {
    width: '100%',
    paddingHorizontal: 16,
    paddingVertical: 12,
    backgroundColor: '#f9fafb',
    borderWidth: 1,
    borderColor: '#e5e7eb',
    borderRadius: 12,
    fontSize: 16,
    color: '#111827',
  },
  textArea: {
    width: '100%',
    paddingHorizontal: 16,
    paddingVertical: 12,
    backgroundColor: '#f9fafb',
    borderWidth: 1,
    borderColor: '#e5e7eb',
    borderRadius: 12,
    fontSize: 16,
    color: '#111827',
    minHeight: 100,
  },
  charCount: {
    fontSize: 12,
    color: '#9ca3af',
    marginTop: 4,
    marginLeft: 4,
  },
  label: {
    fontSize: 14,
    fontWeight: 'bold',
    color: '#111827',
    marginBottom: 12,
  },
  pickerButton: {
    width: '100%',
    paddingHorizontal: 16,
    paddingVertical: 12,
    backgroundColor: '#f9fafb',
    borderWidth: 1,
    borderColor: '#e5e7eb',
    borderRadius: 12,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  pickerButtonText: {
    fontSize: 16,
    color: '#111827',
  },
  pickerButtonTextPlaceholder: {
    color: '#9ca3af',
  },
  chevronIcon: {
    transform: [{ rotate: '0deg' }],
  },
  chevronIconRotated: {
    transform: [{ rotate: '180deg' }],
  },
  pickerDropdown: {
    marginTop: 8,
    overflow: 'hidden',
  },
  pickerDropdownContent: {
    backgroundColor: '#ffffff',
    borderWidth: 1,
    borderColor: '#e5e7eb',
    borderRadius: 12,
    overflow: 'hidden',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.1,
    shadowRadius: 2,
    elevation: 2,
  },
  pickerOption: {
    width: '100%',
    paddingHorizontal: 16,
    paddingVertical: 12,
    flexDirection: 'row',
    alignItems: 'center',
    borderBottomWidth: 1,
    borderBottomColor: '#f3f4f6',
    gap: 12,
  },
  pickerOptionCondition: {
    alignItems: 'flex-start',
  },
  pickerOptionConditionContent: {
    flex: 1,
  },
  pickerOptionActive: {
    backgroundColor: '#f9fafb',
  },
  pickerOptionText: {
    fontSize: 16,
    fontWeight: '500',
    color: '#111827',
    flex: 1,
  },
  pickerOptionDesc: {
    fontSize: 12,
    color: '#6b7280',
    marginTop: 2,
  },
  pickerOptionIndicator: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: '#154733',
  },
  priceInputContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#f9fafb',
    borderWidth: 1,
    borderColor: '#e5e7eb',
    borderRadius: 12,
    paddingLeft: 16,
  },
  priceSymbol: {
    fontSize: 18,
    fontWeight: '600',
    color: '#111827',
  },
  priceInput: {
    flex: 1,
    paddingVertical: 12,
    paddingLeft: 8,
    fontSize: 18,
    fontWeight: '600',
    color: '#111827',
  },
  priceHint: {
    fontSize: 12,
    color: '#6b7280',
    marginTop: 4,
    marginLeft: 4,
  },
  tipsContainer: {
    marginTop: 8,
    borderRadius: 16,
    overflow: 'hidden',
    borderWidth: 1,
    borderColor: '#dbeafe',
  },
  tipsGradient: {
    padding: 16,
  },
  tipsContent: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: 12,
  },
  tipsIconContainer: {
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: '#ffffff',
    alignItems: 'center',
    justifyContent: 'center',
    flexShrink: 0,
  },
  tipsTextContainer: {
    flex: 1,
  },
  tipsTitle: {
    fontSize: 14,
    fontWeight: 'bold',
    color: '#111827',
    marginBottom: 4,
  },
  tipsList: {
    gap: 4,
  },
  tipsItem: {
    fontSize: 12,
    color: '#4b5563',
    lineHeight: 18,
  },
});
