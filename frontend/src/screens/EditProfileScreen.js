import React, { useState, useEffect, useContext } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  ScrollView,
  Alert,
  Modal,
  FlatList,
  Platform,
  Image,
} from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import * as ImagePicker from 'expo-image-picker';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { AuthContext } from '../context/AuthContext';
import { api } from '../services/api';
import { countries } from '../data/countries';
import SuccessBanner from '../components/SuccessBanner';

export default function EditProfileScreen() {
  const { user, login, logout } = useContext(AuthContext);
  const navigation = useNavigation();
  const [loading, setLoading] = useState(false);
  const [formData, setFormData] = useState({
    username: '',
    firstName: '',
    lastName: '',
    bio: '',
    country: '',
    dateOfBirth: '',
  });
  const [showCountryModal, setShowCountryModal] = useState(false);
  const [showDateModal, setShowDateModal] = useState(false);
  const [selectedYear, setSelectedYear] = useState(new Date().getFullYear());
  const [selectedMonth, setSelectedMonth] = useState(new Date().getMonth() + 1);
  const [selectedDay, setSelectedDay] = useState(new Date().getDate());
  const [showSuccessBanner, setShowSuccessBanner] = useState(false);
  const [avatarUri, setAvatarUri] = useState(null);
  const [uploadingAvatar, setUploadingAvatar] = useState(false);
  const [selectedAvatarUri, setSelectedAvatarUri] = useState(null);
  const [showAvatarPreview, setShowAvatarPreview] = useState(false);

  // Generate years, months, days for date picker
  const getDaysInMonth = (year, month) => {
    return new Date(year, month, 0).getDate();
  };

  const years = Array.from({ length: 100 }, (_, i) => new Date().getFullYear() - i);
  const months = Array.from({ length: 12 }, (_, i) => i + 1);

  useEffect(() => {
    loadUserData();
  }, []);

  // Update days when year or month changes
  useEffect(() => {
    const maxDays = getDaysInMonth(selectedYear, selectedMonth);
    if (selectedDay > maxDays) {
      setSelectedDay(maxDays);
    }
  }, [selectedYear, selectedMonth]);

  const loadUserData = async () => {
    try {
      const response = await api.get(`/users/${user.id}`);
      
      // Parse date string (YYYY-MM-DD) and extract components in local timezone
      let dateStr = '';
      if (response.data.dateOfBirth) {
        const dateValue = response.data.dateOfBirth;
        
        // Handle different date formats
        if (typeof dateValue === 'string') {
          // If it's already in YYYY-MM-DD format, use it directly
          if (dateValue.match(/^\d{4}-\d{2}-\d{2}$/)) {
            dateStr = dateValue;
          } else {
            // If it's an ISO string, extract just the date part
            const date = new Date(dateValue);
            if (!isNaN(date.getTime())) {
              const year = date.getFullYear();
              const month = String(date.getMonth() + 1).padStart(2, '0');
              const day = String(date.getDate()).padStart(2, '0');
              dateStr = `${year}-${month}-${day}`;
            }
          }
        } else if (dateValue instanceof Date) {
          // If it's a Date object
          const year = dateValue.getFullYear();
          const month = String(dateValue.getMonth() + 1).padStart(2, '0');
          const day = String(dateValue.getDate()).padStart(2, '0');
          dateStr = `${year}-${month}-${day}`;
        }
      }
      
      setFormData({
        username: response.data.username || '',
        firstName: response.data.firstName || '',
        lastName: response.data.lastName || '',
        bio: response.data.bio || '',
        country: response.data.country || '',
        dateOfBirth: dateStr,
      });

      // Set avatar
      if (response.data.avatar) {
        setAvatarUri(response.data.avatar);
      }

      // Initialize date picker if date exists
      if (dateStr) {
        const [year, month, day] = dateStr.split('-').map(Number);
        setSelectedYear(year);
        setSelectedMonth(month);
        setSelectedDay(day);
      }
    } catch (error) {
      Alert.alert('Error', 'Failed to load profile data');
    }
  };

  const handleSave = async () => {
    if (!formData.username.trim()) {
      Alert.alert('Error', 'Username is required');
      return;
    }

    if (loading) return; // Prevent double-clicks

    setLoading(true);
    try {
      // Prepare update data - send all fields
      const updateData = {
        username: formData.username.trim(),
        firstName: formData.firstName ? formData.firstName.trim() : null,
        lastName: formData.lastName ? formData.lastName.trim() : null,
        bio: formData.bio ? formData.bio.trim() : null,
        country: formData.country || null,
        dateOfBirth: formData.dateOfBirth || null,
      };

      console.log('Sending update request:', updateData);
      const response = await api.put(`/users/${user.id}`, updateData);
      console.log('Update response:', response.data);
      
      // Update auth context with new user data
      const token = await AsyncStorage.getItem('token');
      const updatedUser = { ...user, ...response.data };
      if (token) {
        await login(token, updatedUser);
      }

      // Reset loading state immediately to prevent glitch
      setLoading(false);
      
      // Show success banner
      setShowSuccessBanner(true);
      console.log('Banner should be visible now');
      
      // Navigate back after banner shows for 2 seconds
      setTimeout(() => {
        console.log('Navigating back...');
        setShowSuccessBanner(false);
        setTimeout(() => {
          navigation.goBack();
        }, 300);
      }, 2000);
    } catch (error) {
      console.error('Save error:', error);
      console.error('Error response:', error.response?.data);
      console.error('Error status:', error.response?.status);
      const errorMessage = error.response?.data?.message || error.response?.data?.error || error.message || 'Failed to update profile';
      Alert.alert('Error', errorMessage);
      setLoading(false);
    }
  };

  const handleDeleteAccount = () => {
    Alert.alert(
      'Delete Account',
      'Are you sure you want to delete your account? This action cannot be undone and will permanently delete all your data including products, orders, and messages.',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete',
          style: 'destructive',
          onPress: () => {
            Alert.alert(
              'Final Confirmation',
              'Type "DELETE" to confirm account deletion',
              [
                { text: 'Cancel', style: 'cancel' },
                {
                  text: 'Confirm',
                  style: 'destructive',
                  onPress: confirmDeleteAccount,
                },
              ]
            );
          },
        },
      ]
    );
  };

  const confirmDeleteAccount = async () => {
    setLoading(true);
    try {
      await api.delete(`/users/${user.id}`);
      Alert.alert('Account Deleted', 'Your account has been deleted successfully.', [
        {
          text: 'OK',
          onPress: async () => {
            await logout();
            navigation.reset({
              index: 0,
              routes: [{ name: 'Login' }],
            });
          },
        },
      ]);
    } catch (error) {
      Alert.alert('Error', error.response?.data?.message || 'Failed to delete account');
      setLoading(false);
    }
  };

  const formatDate = (dateString) => {
    if (!dateString) return 'Not set';
    try {
      // Parse YYYY-MM-DD string and create date in local timezone
      if (dateString.match(/^\d{4}-\d{2}-\d{2}$/)) {
        const [year, month, day] = dateString.split('-').map(Number);
        const date = new Date(year, month - 1, day); // month is 0-indexed
        if (isNaN(date.getTime())) {
          return 'Invalid date';
        }
        return date.toLocaleDateString('en-US', {
          year: 'numeric',
          month: 'long',
          day: 'numeric',
        });
      }
      // Fallback for other date formats
      const date = new Date(dateString);
      if (isNaN(date.getTime())) {
        return 'Invalid date';
      }
      return date.toLocaleDateString('en-US', {
        year: 'numeric',
        month: 'long',
        day: 'numeric',
      });
    } catch (error) {
      return 'Invalid date';
    }
  };

  const handleDateSelect = () => {
    // Format as YYYY-MM-DD directly from selected values (no Date object conversion)
    const year = selectedYear;
    const month = String(selectedMonth).padStart(2, '0');
    const day = String(selectedDay).padStart(2, '0');
    const dateStr = `${year}-${month}-${day}`;
    setFormData({ ...formData, dateOfBirth: dateStr });
    setShowDateModal(false);
  };

  const handleCountrySelect = (country) => {
    setFormData({ ...formData, country });
    setShowCountryModal(false);
  };

  const pickAvatar = async () => {
    const { status } = await ImagePicker.requestMediaLibraryPermissionsAsync();
    if (status !== 'granted') {
      Alert.alert('Permission needed', 'Please grant camera roll permissions');
      return;
    }

    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ImagePicker.MediaTypeOptions.Images,
      allowsEditing: true, // Native editor with pan/zoom
      aspect: [1, 1], // Square crop
      quality: 0.8,
    });

    if (!result.canceled && result.assets[0]) {
      const imageUri = result.assets[0].uri;
      setSelectedAvatarUri(imageUri);
      setShowAvatarPreview(true);
    }
  };

  const confirmAvatarCrop = async () => {
    if (selectedAvatarUri) {
      setShowAvatarPreview(false);
      // Upload the image (already cropped by native picker)
      // The native picker with allowsEditing: true already handles cropping
      await uploadAvatar(selectedAvatarUri);
    }
  };

  const cancelAvatarCrop = () => {
    setSelectedAvatarUri(null);
    setShowAvatarPreview(false);
  };

  const uploadAvatar = async (uri) => {
    setUploadingAvatar(true);
    try {
      const formData = new FormData();
      
      // Handle web vs mobile file upload differently
      if (Platform.OS === 'web') {
        // For web, we need to fetch the image and convert it to a blob
        const response = await fetch(uri);
        const blob = await response.blob();
        formData.append('avatar', blob, 'avatar.jpg');
      } else {
        // For mobile, use the uri directly
        formData.append('avatar', {
          uri,
          type: 'image/jpeg',
          name: 'avatar.jpg',
        });
      }

      console.log('Uploading avatar...');
      const response = await api.post(`/users/${user.id}/avatar`, formData, {
        headers: {
          'Content-Type': 'multipart/form-data',
        },
      });

      console.log('Avatar upload response:', response.data);

      // Update auth context with new avatar
      const token = await AsyncStorage.getItem('token');
      const updatedUser = { ...user, ...response.data };
      if (token) {
        await login(token, updatedUser);
      }

      setAvatarUri(response.data.avatar);
      setSelectedAvatarUri(null);
      
      // Show success banner
      setShowSuccessBanner(true);
      setTimeout(() => {
        setShowSuccessBanner(false);
      }, 2000);
    } catch (error) {
      console.error('Upload avatar error:', error);
      console.error('Error details:', error.response?.data);
      Alert.alert('Error', error.response?.data?.message || 'Failed to upload avatar');
      // Revert to previous avatar on error
      const userResponse = await api.get(`/users/${user.id}`);
      setAvatarUri(userResponse.data.avatar || null);
    } finally {
      setUploadingAvatar(false);
    }
  };

  return (
    <View style={styles.container}>
      <SuccessBanner
        message="Profile Saved"
        visible={showSuccessBanner}
        onHide={() => setShowSuccessBanner(false)}
      />
      <ScrollView style={styles.scrollView}>
      <View style={styles.header}>
        <TouchableOpacity onPress={() => navigation.goBack()} style={styles.backButton}>
          <Ionicons name="arrow-back" size={24} color="#000" />
        </TouchableOpacity>
        <Text style={styles.headerTitle}>Edit Profile</Text>
        <TouchableOpacity
          onPress={handleSave}
          style={[styles.saveButton, loading && styles.saveButtonDisabled]}
          disabled={loading}
          activeOpacity={0.7}
        >
          <Text style={styles.saveButtonText}>{loading ? 'Applying...' : 'Apply'}</Text>
        </TouchableOpacity>
      </View>

      <View style={styles.form}>
        <View style={styles.avatarSection}>
          <View style={styles.avatarContainer}>
            <Image
              source={{
                uri: avatarUri || user?.avatar || 'https://via.placeholder.com/150',
              }}
              style={styles.avatar}
            />
            {uploadingAvatar && (
              <View style={styles.avatarOverlay}>
                <Text style={styles.uploadingText}>Uploading...</Text>
              </View>
            )}
          </View>
          <TouchableOpacity
            style={styles.changeAvatarButton}
            onPress={pickAvatar}
            disabled={uploadingAvatar}
          >
            <Ionicons name="camera-outline" size={20} color="#000" />
            <Text style={styles.changeAvatarText}>
              {uploadingAvatar ? 'Uploading...' : 'Change Photo'}
            </Text>
          </TouchableOpacity>
        </View>

        <View style={styles.inputGroup}>
          <Text style={styles.label}>Username *</Text>
          <TextInput
            style={styles.input}
            value={formData.username}
            onChangeText={(text) => setFormData({ ...formData, username: text })}
            placeholder="Username"
            autoCapitalize="none"
          />
        </View>

        <View style={styles.row}>
          <View style={[styles.inputGroup, styles.halfWidth]}>
            <Text style={styles.label}>First Name</Text>
            <TextInput
              style={styles.input}
              value={formData.firstName}
              onChangeText={(text) => setFormData({ ...formData, firstName: text })}
              placeholder="First Name"
            />
          </View>

          <View style={[styles.inputGroup, styles.halfWidth]}>
            <Text style={styles.label}>Last Name</Text>
            <TextInput
              style={styles.input}
              value={formData.lastName}
              onChangeText={(text) => setFormData({ ...formData, lastName: text })}
              placeholder="Last Name"
            />
          </View>
        </View>

        <View style={styles.inputGroup}>
          <Text style={styles.label}>Bio</Text>
          <TextInput
            style={[styles.input, styles.textArea]}
            value={formData.bio}
            onChangeText={(text) => setFormData({ ...formData, bio: text })}
            placeholder="Tell us about yourself..."
            multiline
            numberOfLines={4}
          />
        </View>

        <View style={styles.inputGroup}>
          <Text style={styles.label}>Country</Text>
          <TouchableOpacity
            style={styles.pickerButton}
            onPress={() => setShowCountryModal(true)}
          >
            <Text style={[styles.pickerText, !formData.country && styles.placeholderText]}>
              {formData.country || 'Select Country'}
            </Text>
            <Ionicons name="chevron-down" size={20} color="#666" />
          </TouchableOpacity>
        </View>

        <View style={styles.inputGroup}>
          <Text style={styles.label}>Date of Birth</Text>
          <TouchableOpacity
            style={styles.pickerButton}
            onPress={() => {
              // Initialize date picker with current date or existing date
              if (formData.dateOfBirth) {
                // Parse YYYY-MM-DD string in local timezone
                const [year, month, day] = formData.dateOfBirth.split('-').map(Number);
                setSelectedYear(year);
                setSelectedMonth(month);
                setSelectedDay(day);
              }
              setShowDateModal(true);
            }}
          >
            <Text style={[styles.pickerText, !formData.dateOfBirth && styles.placeholderText]}>
              {formData.dateOfBirth ? formatDate(formData.dateOfBirth) : 'Select Date of Birth'}
            </Text>
            <Ionicons name="calendar-outline" size={20} color="#666" />
          </TouchableOpacity>
        </View>
      </View>

      <View style={styles.dangerZone}>
        <Text style={styles.dangerZoneTitle}>Danger Zone</Text>
        <TouchableOpacity
          style={styles.deleteButton}
          onPress={handleDeleteAccount}
          disabled={loading}
        >
          <Ionicons name="trash-outline" size={20} color="#ff4444" />
          <Text style={styles.deleteButtonText}>Delete Account</Text>
        </TouchableOpacity>
        <Text style={styles.dangerZoneText}>
          Once you delete your account, there is no going back. Please be certain.
        </Text>
      </View>

      {/* Country Picker Modal */}
      <Modal
        visible={showCountryModal}
        transparent={true}
        animationType="slide"
        onRequestClose={() => setShowCountryModal(false)}
      >
        <View style={styles.modalOverlay}>
          <View style={styles.modalContent}>
            <View style={styles.modalHeader}>
              <Text style={styles.modalTitle}>Select Country</Text>
              <TouchableOpacity
                onPress={() => setShowCountryModal(false)}
                style={styles.modalCloseButton}
              >
                <Ionicons name="close" size={24} color="#000" />
              </TouchableOpacity>
            </View>
            <FlatList
              data={countries}
              keyExtractor={(item) => item}
              renderItem={({ item }) => (
                <TouchableOpacity
                  style={[
                    styles.countryItem,
                    formData.country === item && styles.countryItemSelected,
                  ]}
                  onPress={() => handleCountrySelect(item)}
                >
                  <Text
                    style={[
                      styles.countryItemText,
                      formData.country === item && styles.countryItemTextSelected,
                    ]}
                  >
                    {item}
                  </Text>
                  {formData.country === item && (
                    <Ionicons name="checkmark" size={20} color="#000" />
                  )}
                </TouchableOpacity>
              )}
            />
          </View>
        </View>
      </Modal>

      {/* Date Picker Modal */}
      <Modal
        visible={showDateModal}
        transparent={true}
        animationType="slide"
        onRequestClose={() => setShowDateModal(false)}
      >
        <View style={styles.modalOverlay}>
          <View style={styles.modalContent}>
            <View style={styles.modalHeader}>
              <Text style={styles.modalTitle}>Select Date of Birth</Text>
              <TouchableOpacity
                onPress={() => setShowDateModal(false)}
                style={styles.modalCloseButton}
              >
                <Ionicons name="close" size={24} color="#000" />
              </TouchableOpacity>
            </View>
            <View style={styles.datePickerContainer}>
              <View style={styles.datePickerColumn}>
                <Text style={styles.datePickerLabel}>Year</Text>
                <ScrollView style={styles.datePickerScroll}>
                  {years.map((year) => (
                    <TouchableOpacity
                      key={year}
                      style={[
                        styles.datePickerItem,
                        selectedYear === year && styles.datePickerItemSelected,
                      ]}
                      onPress={() => setSelectedYear(year)}
                    >
                      <Text
                        style={[
                          styles.datePickerItemText,
                          selectedYear === year && styles.datePickerItemTextSelected,
                        ]}
                      >
                        {year}
                      </Text>
                    </TouchableOpacity>
                  ))}
                </ScrollView>
              </View>
              <View style={styles.datePickerColumn}>
                <Text style={styles.datePickerLabel}>Month</Text>
                <ScrollView style={styles.datePickerScroll}>
                  {months.map((month) => (
                    <TouchableOpacity
                      key={month}
                      style={[
                        styles.datePickerItem,
                        selectedMonth === month && styles.datePickerItemSelected,
                      ]}
                      onPress={() => setSelectedMonth(month)}
                    >
                      <Text
                        style={[
                          styles.datePickerItemText,
                          selectedMonth === month && styles.datePickerItemTextSelected,
                        ]}
                      >
                        {new Date(2000, month - 1).toLocaleString('default', { month: 'long' })}
                      </Text>
                    </TouchableOpacity>
                  ))}
                </ScrollView>
              </View>
              <View style={styles.datePickerColumn}>
                <Text style={styles.datePickerLabel}>Day</Text>
                <ScrollView style={styles.datePickerScroll}>
                  {Array.from(
                    { length: getDaysInMonth(selectedYear, selectedMonth) },
                    (_, i) => i + 1
                  ).map((day) => (
                    <TouchableOpacity
                      key={day}
                      style={[
                        styles.datePickerItem,
                        selectedDay === day && styles.datePickerItemSelected,
                      ]}
                      onPress={() => setSelectedDay(day)}
                    >
                      <Text
                        style={[
                          styles.datePickerItemText,
                          selectedDay === day && styles.datePickerItemTextSelected,
                        ]}
                      >
                        {day}
                      </Text>
                    </TouchableOpacity>
                  ))}
                </ScrollView>
              </View>
            </View>
            <View style={styles.datePickerActions}>
              <TouchableOpacity
                style={styles.dateClearButton}
                onPress={() => {
                  setFormData({ ...formData, dateOfBirth: '' });
                  setShowDateModal(false);
                }}
              >
                <Text style={styles.dateClearButtonText}>Clear</Text>
              </TouchableOpacity>
              <TouchableOpacity style={styles.dateConfirmButton} onPress={handleDateSelect}>
                <Text style={styles.dateConfirmButtonText}>Confirm</Text>
              </TouchableOpacity>
            </View>
          </View>
        </View>
      </Modal>

      {/* Avatar Preview Modal with Crop */}
      <Modal
        visible={showAvatarPreview}
        transparent={true}
        animationType="slide"
        onRequestClose={cancelAvatarCrop}
      >
        <View style={styles.avatarPreviewContainer}>
          <View style={styles.avatarPreviewContent}>
            <View style={styles.avatarPreviewHeader}>
              <Text style={styles.avatarPreviewTitle}>Adjust Your Photo</Text>
              <TouchableOpacity
                onPress={cancelAvatarCrop}
                style={styles.avatarPreviewCloseButton}
              >
                <Ionicons name="close" size={24} color="#000" />
              </TouchableOpacity>
            </View>
            
            <View style={styles.avatarPreviewImageContainer}>
              <Image
                source={{ uri: selectedAvatarUri }}
                style={styles.avatarPreviewImage}
                resizeMode="cover"
              />
              <View style={styles.cropOverlay}>
                <View style={styles.cropFrame} />
              </View>
            </View>
            
            <Text style={styles.avatarPreviewHint}>
              Preview your cropped image. Click Apply to save.
            </Text>
            
            <View style={styles.avatarPreviewActions}>
              <TouchableOpacity
                style={styles.avatarPreviewCancelButton}
                onPress={cancelAvatarCrop}
              >
                <Text style={styles.avatarPreviewCancelText}>Cancel</Text>
              </TouchableOpacity>
              <TouchableOpacity
                style={styles.avatarPreviewConfirmButton}
                onPress={confirmAvatarCrop}
                disabled={uploadingAvatar}
              >
                <Text style={styles.avatarPreviewConfirmText}>
                  {uploadingAvatar ? 'Uploading...' : 'Apply'}
                </Text>
              </TouchableOpacity>
            </View>
          </View>
        </View>
      </Modal>
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
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: 15,
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
  },
  backButton: {
    padding: 5,
  },
  headerTitle: {
    fontSize: 18,
    fontWeight: '600',
    flex: 1,
    textAlign: 'center',
  },
  saveButton: {
    paddingHorizontal: 15,
    paddingVertical: 8,
  },
  saveButtonDisabled: {
    opacity: 0.5,
  },
  saveButtonText: {
    fontSize: 16,
    fontWeight: '600',
    color: '#000',
  },
  form: {
    padding: 15,
  },
  avatarSection: {
    alignItems: 'center',
    marginBottom: 30,
    paddingVertical: 20,
  },
  avatarContainer: {
    position: 'relative',
    marginBottom: 15,
  },
  avatar: {
    width: 120,
    height: 120,
    borderRadius: 60,
    backgroundColor: '#f0f0f0',
  },
  avatarOverlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    borderRadius: 60,
    backgroundColor: 'rgba(0, 0, 0, 0.5)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  uploadingText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '600',
  },
  changeAvatarButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 10,
    paddingHorizontal: 20,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: '#ddd',
    backgroundColor: '#fff',
  },
  changeAvatarText: {
    marginLeft: 8,
    fontSize: 16,
    fontWeight: '600',
    color: '#000',
  },
  inputGroup: {
    marginBottom: 20,
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
    backgroundColor: '#fff',
  },
  textArea: {
    height: 100,
    textAlignVertical: 'top',
  },
  row: {
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  halfWidth: {
    width: '48%',
  },
  pickerButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    borderWidth: 1,
    borderColor: '#ddd',
    borderRadius: 8,
    padding: 12,
    backgroundColor: '#fff',
  },
  pickerText: {
    fontSize: 16,
    color: '#333',
  },
  placeholderText: {
    color: '#999',
  },
  modalOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.5)',
    justifyContent: 'flex-end',
  },
  modalContent: {
    backgroundColor: '#fff',
    borderTopLeftRadius: 20,
    borderTopRightRadius: 20,
    maxHeight: '80%',
    paddingBottom: 20,
  },
  modalHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: 20,
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
  },
  modalTitle: {
    fontSize: 18,
    fontWeight: '600',
  },
  modalCloseButton: {
    padding: 5,
  },
  countryItem: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: 15,
    borderBottomWidth: 1,
    borderBottomColor: '#f0f0f0',
  },
  countryItemSelected: {
    backgroundColor: '#f5f5f5',
  },
  countryItemText: {
    fontSize: 16,
    color: '#333',
  },
  countryItemTextSelected: {
    fontWeight: '600',
    color: '#000',
  },
  datePickerContainer: {
    flexDirection: 'row',
    height: 300,
    padding: 10,
  },
  datePickerColumn: {
    flex: 1,
    marginHorizontal: 5,
  },
  datePickerLabel: {
    fontSize: 14,
    fontWeight: '600',
    textAlign: 'center',
    marginBottom: 10,
    color: '#666',
  },
  datePickerScroll: {
    flex: 1,
  },
  datePickerItem: {
    padding: 12,
    alignItems: 'center',
    borderRadius: 8,
    marginBottom: 5,
  },
  datePickerItemSelected: {
    backgroundColor: '#154733',
  },
  datePickerItemText: {
    fontSize: 16,
    color: '#333',
  },
  datePickerItemTextSelected: {
    color: '#fff',
    fontWeight: '600',
  },
  datePickerActions: {
    flexDirection: 'row',
    padding: 20,
    gap: 10,
  },
  dateClearButton: {
    flex: 1,
    backgroundColor: '#fff',
    borderWidth: 1,
    borderColor: '#ddd',
    padding: 15,
    borderRadius: 8,
    alignItems: 'center',
  },
  dateClearButtonText: {
    color: '#666',
    fontSize: 16,
    fontWeight: '600',
  },
  dateConfirmButton: {
    flex: 1,
    backgroundColor: '#154733',
    padding: 15,
    borderRadius: 8,
    alignItems: 'center',
  },
  dateConfirmButtonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
  dangerZone: {
    marginTop: 30,
    marginBottom: 30,
    padding: 20,
    borderTopWidth: 1,
    borderTopColor: '#eee',
  },
  dangerZoneTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: '#ff4444',
    marginBottom: 15,
  },
  deleteButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#fff',
    borderWidth: 2,
    borderColor: '#ff4444',
    borderRadius: 8,
    padding: 15,
    marginBottom: 10,
  },
  deleteButtonText: {
    fontSize: 16,
    fontWeight: '600',
    color: '#ff4444',
    marginLeft: 8,
  },
  dangerZoneText: {
    fontSize: 12,
    color: '#666',
    textAlign: 'center',
  },
  avatarPreviewContainer: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.9)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  avatarPreviewContent: {
    width: '90%',
    maxWidth: 400,
    backgroundColor: '#fff',
    borderRadius: 20,
    padding: 20,
  },
  avatarPreviewHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 20,
  },
  avatarPreviewTitle: {
    fontSize: 18,
    fontWeight: '600',
  },
  avatarPreviewCloseButton: {
    padding: 5,
  },
  avatarPreviewImageContainer: {
    width: '100%',
    height: 300,
    marginBottom: 15,
    borderRadius: 10,
    overflow: 'hidden',
    backgroundColor: '#f0f0f0',
    position: 'relative',
  },
  avatarPreviewImage: {
    width: '100%',
    height: '100%',
  },
  cropOverlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    justifyContent: 'center',
    alignItems: 'center',
  },
  cropFrame: {
    width: 250,
    height: 250,
    borderRadius: 125,
    borderWidth: 3,
    borderColor: '#fff',
    borderStyle: 'dashed',
  },
  avatarPreviewHint: {
    fontSize: 14,
    color: '#666',
    textAlign: 'center',
    marginBottom: 20,
  },
  avatarPreviewActions: {
    flexDirection: 'row',
    gap: 10,
  },
  avatarPreviewCancelButton: {
    flex: 1,
    padding: 15,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: '#ddd',
    alignItems: 'center',
    backgroundColor: '#fff',
  },
  avatarPreviewCancelText: {
    fontSize: 16,
    fontWeight: '600',
    color: '#666',
  },
  avatarPreviewConfirmButton: {
    flex: 1,
    padding: 15,
    borderRadius: 8,
    alignItems: 'center',
    backgroundColor: '#154733',
  },
  avatarPreviewConfirmText: {
    fontSize: 16,
    fontWeight: '600',
    color: '#fff',
  },
});

