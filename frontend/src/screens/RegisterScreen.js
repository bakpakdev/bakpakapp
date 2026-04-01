import React, { useState, useContext } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  KeyboardAvoidingView,
  Platform,
  Alert,
  ScrollView,
} from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { api } from '../services/api';
import { AuthContext } from '../context/AuthContext';
import BakpakLogo from '../components/BakpakLogo';

export default function RegisterScreen({ navigation }) {
  const [formData, setFormData] = useState({
    email: '',
    username: '',
    password: '',
    firstName: '',
    lastName: '',
  });
  const [loading, setLoading] = useState(false);
  const { login } = useContext(AuthContext);

  const handleRegister = async () => {
    if (!formData.email || !formData.username || !formData.password) {
      Alert.alert('Error', 'Please fill in all required fields');
      return;
    }

    setLoading(true);
    try {
      const response = await api.post('/auth/register', formData);
      await login(response.data.token, response.data.user);
    } catch (error) {
      Alert.alert('Error', error.response?.data?.message || 'Registration failed');
    } finally {
      setLoading(false);
    }
  };

  return (
    <KeyboardAvoidingView
      behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
      style={styles.container}
    >
      <LinearGradient
        colors={['#f8f9fa', '#e9ecef', '#ffffff']}
        style={styles.gradient}
      >
        <ScrollView contentContainerStyle={styles.content}>
          <View style={styles.logoContainer}>
            <BakpakLogo size={100} color="#000" />
          </View>
          <Text style={styles.title}>Create Account</Text>
          <Text style={styles.subtitle}>Join bakpak today</Text>

        <TextInput
          style={styles.input}
          placeholder="Email *"
          value={formData.email}
          onChangeText={(text) => setFormData({ ...formData, email: text })}
          keyboardType="email-address"
          autoCapitalize="none"
        />

        <TextInput
          style={styles.input}
          placeholder="Username *"
          value={formData.username}
          onChangeText={(text) => setFormData({ ...formData, username: text })}
          autoCapitalize="none"
        />

        <TextInput
          style={styles.input}
          placeholder="First Name"
          value={formData.firstName}
          onChangeText={(text) => setFormData({ ...formData, firstName: text })}
        />

        <TextInput
          style={styles.input}
          placeholder="Last Name"
          value={formData.lastName}
          onChangeText={(text) => setFormData({ ...formData, lastName: text })}
        />

        <TextInput
          style={styles.input}
          placeholder="Password *"
          value={formData.password}
          onChangeText={(text) => setFormData({ ...formData, password: text })}
          secureTextEntry
        />

        <TouchableOpacity
          style={[styles.button, loading && styles.buttonDisabled]}
          onPress={handleRegister}
          disabled={loading}
        >
          <Text style={styles.buttonText}>{loading ? 'Creating account...' : 'Sign Up'}</Text>
        </TouchableOpacity>

        <TouchableOpacity
          onPress={() => navigation.navigate('Login')}
          style={styles.linkButton}
        >
          <Text style={styles.linkText}>
            Already have an account? <Text style={styles.linkTextBold}>Login</Text>
          </Text>
        </TouchableOpacity>
        </ScrollView>
      </LinearGradient>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  gradient: {
    flex: 1,
  },
  content: {
    padding: 30,
    paddingTop: 60,
  },
  logoContainer: {
    alignItems: 'center',
    marginBottom: 20,
  },
  title: {
    fontSize: 36,
    fontWeight: 'bold',
    textAlign: 'center',
    marginBottom: 8,
    color: '#000',
    letterSpacing: 1,
  },
  subtitle: {
    fontSize: 16,
    color: '#666',
    textAlign: 'center',
    marginBottom: 40,
  },
  input: {
    borderWidth: 1.5,
    borderColor: '#e0e0e0',
    borderRadius: 12,
    padding: 16,
    marginBottom: 16,
    fontSize: 16,
    backgroundColor: '#fff',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.05,
    shadowRadius: 2,
    elevation: 1,
  },
  button: {
    backgroundColor: '#154733',
    padding: 16,
    borderRadius: 12,
    alignItems: 'center',
    marginTop: 10,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.2,
    shadowRadius: 4,
    elevation: 3,
  },
  buttonDisabled: {
    opacity: 0.6,
  },
  buttonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
    letterSpacing: 0.5,
  },
  linkButton: {
    marginTop: 24,
    alignItems: 'center',
  },
  linkText: {
    color: '#666',
    fontSize: 14,
  },
  linkTextBold: {
    fontWeight: '600',
    color: '#000',
  },
});

