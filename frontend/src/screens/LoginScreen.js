import React, { useState, useContext, useEffect, useRef } from 'react';
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
  ActivityIndicator,
  Animated,
  Image,
} from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { api } from '../services/api';
import { AuthContext } from '../context/AuthContext';
import { Ionicons } from '@expo/vector-icons';

export default function LoginScreen({ navigation }) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState('');
  const { login } = useContext(AuthContext);

  // Animation values
  const logoOpacity = useRef(new Animated.Value(0)).current;
  const logoScale = useRef(new Animated.Value(0.9)).current;
  const welcomeOpacity = useRef(new Animated.Value(0)).current;
  const welcomeY = useRef(new Animated.Value(10)).current;
  const formOpacity = useRef(new Animated.Value(0)).current;
  const formY = useRef(new Animated.Value(10)).current;
  const signUpOpacity = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    // Use native driver only on native platforms, not on web
    const useNativeDriver = Platform.OS !== 'web';

    // Logo animation
    Animated.parallel([
      Animated.timing(logoOpacity, {
        toValue: 1,
        duration: 400,
        useNativeDriver: useNativeDriver,
      }),
      Animated.spring(logoScale, {
        toValue: 1,
        tension: 50,
        friction: 7,
        useNativeDriver: useNativeDriver,
      }),
    ]).start();

    // Welcome text animation
    Animated.parallel([
      Animated.timing(welcomeOpacity, {
        toValue: 1,
        duration: 400,
        delay: 100,
        useNativeDriver: useNativeDriver,
      }),
      Animated.timing(welcomeY, {
        toValue: 0,
        duration: 400,
        delay: 100,
        useNativeDriver: useNativeDriver,
      }),
    ]).start();

    // Form animation
    Animated.parallel([
      Animated.timing(formOpacity, {
        toValue: 1,
        duration: 400,
        delay: 200,
        useNativeDriver: useNativeDriver,
      }),
      Animated.timing(formY, {
        toValue: 0,
        duration: 400,
        delay: 200,
        useNativeDriver: useNativeDriver,
      }),
    ]).start();

    // Sign up link animation
    Animated.timing(signUpOpacity, {
      toValue: 1,
      duration: 400,
      delay: 300,
      useNativeDriver: useNativeDriver,
    }).start();
  }, []);

  const handleLogin = async () => {
    if (!email || !password) {
      Alert.alert('Error', 'Please fill in all fields');
      return;
    }

    setLoading(true);
    setErrorMessage('');
    try {
      const response = await api.post('/auth/login', { email, password });
      await login(response.data.token, response.data.user);
    } catch (error) {
      console.log('Login error details:', error);
      console.log('Error response:', error.response);
      console.log('Error response data:', error.response?.data);
      
      let message = 'Login failed. Please try again.';
      
      if (error.response?.data) {
        if (error.response.data.errors && Array.isArray(error.response.data.errors)) {
          message = error.response.data.errors.map(e => e.msg || e.message).join(', ');
        } else if (error.response.data.message) {
          message = error.response.data.message;
        }
      } else if (error.message) {
        message = error.message;
      }
      
      console.log('Error message:', message);
      setErrorMessage(message);
      Alert.alert('Login Error', message);
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
        colors={['#f9fafb', '#f3f4f6', '#ffffff']}
        style={styles.gradient}
      >
        <ScrollView
          contentContainerStyle={styles.scrollContent}
          showsVerticalScrollIndicator={false}
          keyboardShouldPersistTaps="handled"
        >
          {/* Logo */}
          <Animated.View
            style={[
              styles.logoContainer,
              {
                opacity: logoOpacity,
                transform: [{ scale: logoScale }],
              },
            ]}
          >
            <Image
              source={require('../../assets/logo.png')}
              style={styles.logoImage}
              resizeMode="contain"
            />
          </Animated.View>

          {/* Welcome Text */}
          <Animated.View
            style={[
              styles.welcomeContainer,
              {
                opacity: welcomeOpacity,
                transform: [{ translateY: welcomeY }],
              },
            ]}
          >
            <Text style={styles.welcomeTitle}>Welcome Back</Text>
            <Text style={styles.welcomeSubtitle}>Sign in to continue</Text>
          </Animated.View>

          {/* Error Message */}
          {errorMessage ? (
            <View style={styles.errorContainer}>
              <Text style={styles.errorText}>{errorMessage}</Text>
            </View>
          ) : null}

          {/* Login Form */}
          <Animated.View
            style={[
              styles.formContainer,
              {
                opacity: formOpacity,
                transform: [{ translateY: formY }],
              },
            ]}
          >
            {/* Email Input */}
            <View style={styles.inputGroup}>
              <Text style={styles.label}>Email</Text>
              <View style={styles.inputWrapper}>
                <Ionicons
                  name="mail-outline"
                  size={20}
                  color="#9ca3af"
                  style={styles.inputIcon}
                />
                <TextInput
                  style={styles.input}
                  placeholder="Enter your email"
                  placeholderTextColor="#9ca3af"
                  value={email}
                  onChangeText={setEmail}
                  keyboardType="email-address"
                  autoCapitalize="none"
                  autoComplete="email"
                />
              </View>
            </View>

            {/* Password Input */}
            <View style={styles.inputGroup}>
              <Text style={styles.label}>Password</Text>
              <View style={styles.inputWrapper}>
                <Ionicons
                  name="lock-closed-outline"
                  size={20}
                  color="#9ca3af"
                  style={styles.inputIcon}
                />
                <TextInput
                  style={[styles.input, styles.passwordInput]}
                  placeholder="Enter your password"
                  placeholderTextColor="#9ca3af"
                  value={password}
                  onChangeText={setPassword}
                  secureTextEntry={!showPassword}
                  autoCapitalize="none"
                  autoComplete="password"
                />
                <TouchableOpacity
                  onPress={() => setShowPassword(!showPassword)}
                  style={styles.eyeButton}
                  activeOpacity={0.7}
                >
                  <Ionicons
                    name={showPassword ? 'eye-off-outline' : 'eye-outline'}
                    size={20}
                    color="#9ca3af"
                  />
                </TouchableOpacity>
              </View>
            </View>

            {/* Forgot Password */}
            <TouchableOpacity style={styles.forgotPassword}>
              <Text style={styles.forgotPasswordText}>Forgot Password?</Text>
            </TouchableOpacity>

            {/* Submit Button */}
            <TouchableOpacity
              style={[styles.submitButton, loading && styles.submitButtonDisabled]}
              onPress={handleLogin}
              disabled={loading}
              activeOpacity={0.9}
            >
              {loading ? (
                <View style={styles.loadingContainer}>
                  <ActivityIndicator size="small" color="#fff" />
                  <Text style={styles.submitButtonText}>Signing in...</Text>
                </View>
              ) : (
                <Text style={styles.submitButtonText}>Sign In</Text>
              )}
            </TouchableOpacity>

            {/* Divider */}
            <View style={styles.divider}>
              <View style={styles.dividerLine} />
              <Text style={styles.dividerText}>OR</Text>
              <View style={styles.dividerLine} />
            </View>

            {/* Social Login */}
            <View style={styles.socialContainer}>
              <TouchableOpacity style={styles.socialButton} activeOpacity={0.8}>
                <SvgGoogleIcon />
                <Text style={styles.socialButtonText}>Continue with Google</Text>
              </TouchableOpacity>

              <TouchableOpacity style={styles.socialButton} activeOpacity={0.8}>
                <SvgAppleIcon />
                <Text style={styles.socialButtonText}>Continue with Apple</Text>
              </TouchableOpacity>
            </View>
          </Animated.View>

          {/* Sign Up Link */}
          <Animated.View
            style={[
              styles.signUpContainer,
              { opacity: signUpOpacity },
            ]}
          >
            <Text style={styles.signUpText}>
              Don't have an account?{' '}
              <Text
                style={styles.signUpLink}
                onPress={() => navigation.navigate('Register')}
              >
                Sign Up
              </Text>
            </Text>
          </Animated.View>
        </ScrollView>
      </LinearGradient>
    </KeyboardAvoidingView>
  );
}

// Google Icon SVG Component
const SvgGoogleIcon = () => (
  <View style={styles.socialIcon}>
    <View style={{ width: 20, height: 20 }}>
      {/* Google Icon - using a simple colored view as placeholder */}
      <View style={styles.googleIconContainer}>
        <View style={[styles.googleIconPart, { backgroundColor: '#4285F4', borderTopLeftRadius: 2, borderBottomLeftRadius: 2 }]} />
        <View style={[styles.googleIconPart, { backgroundColor: '#34A853', borderTopRightRadius: 2, borderBottomRightRadius: 2 }]} />
        <View style={[styles.googleIconPart, { backgroundColor: '#FBBC05', borderTopLeftRadius: 2, borderTopRightRadius: 2 }]} />
        <View style={[styles.googleIconPart, { backgroundColor: '#EA4335', borderBottomLeftRadius: 2, borderBottomRightRadius: 2 }]} />
      </View>
    </View>
  </View>
);

// Apple Icon SVG Component
const SvgAppleIcon = () => (
  <View style={styles.socialIcon}>
    <Ionicons name="logo-apple" size={20} color="#000" />
  </View>
);

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  gradient: {
    flex: 1,
  },
  scrollContent: {
    flexGrow: 1,
    paddingHorizontal: 24,
    paddingTop: 32,
    paddingBottom: 32,
  },
  logoContainer: {
    alignItems: 'center',
    marginTop: 64,
    marginBottom: 16,
    backgroundColor: 'transparent',
  },
  logoImage: {
    width: 200,
    height: 200,
    backgroundColor: 'transparent',
  },
  welcomeContainer: {
    alignItems: 'center',
    marginBottom: 48,
  },
  welcomeTitle: {
    fontSize: 30,
    fontWeight: 'bold',
    color: '#111827',
    marginBottom: 8,
  },
  welcomeSubtitle: {
    fontSize: 16,
    color: '#6b7280',
  },
  formContainer: {
    flex: 1,
  },
  inputGroup: {
    marginBottom: 20,
  },
  label: {
    fontSize: 14,
    fontWeight: '500',
    color: '#374151',
    marginBottom: 8,
    paddingLeft: 4,
  },
  inputWrapper: {
    position: 'relative',
    flexDirection: 'row',
    alignItems: 'center',
  },
  inputIcon: {
    position: 'absolute',
    left: 16,
    zIndex: 1,
  },
  input: {
    flex: 1,
    backgroundColor: '#fff',
    borderWidth: 1,
    borderColor: '#d1d5db',
    borderRadius: 12,
    paddingVertical: 16,
    paddingLeft: 48,
    paddingRight: 16,
    fontSize: 16,
    color: '#111827',
  },
  passwordInput: {
    paddingRight: 48,
  },
  eyeButton: {
    position: 'absolute',
    right: 16,
    padding: 4,
  },
  forgotPassword: {
    alignItems: 'flex-end',
    marginBottom: 32,
  },
  forgotPasswordText: {
    fontSize: 14,
    fontWeight: '500',
    color: '#6b7280',
  },
  submitButton: {
    width: '100%',
    backgroundColor: '#111827',
    paddingVertical: 16,
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 8,
    elevation: 5,
  },
  submitButtonDisabled: {
    opacity: 0.5,
  },
  submitButtonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
  loadingContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  divider: {
    flexDirection: 'row',
    alignItems: 'center',
    marginVertical: 32,
    gap: 16,
  },
  dividerLine: {
    flex: 1,
    height: 1,
    backgroundColor: '#d1d5db',
  },
  dividerText: {
    fontSize: 12,
    fontWeight: '500',
    color: '#6b7280',
  },
  socialContainer: {
    gap: 12,
    marginBottom: 32,
  },
  socialButton: {
    width: '100%',
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 12,
    backgroundColor: '#fff',
    borderWidth: 1,
    borderColor: '#d1d5db',
    borderRadius: 12,
    paddingVertical: 16,
  },
  socialIcon: {
    width: 20,
    height: 20,
  },
  googleIconContainer: {
    width: 20,
    height: 20,
    flexDirection: 'row',
    flexWrap: 'wrap',
  },
  googleIconPart: {
    width: '50%',
    height: '50%',
  },
  socialButtonText: {
    fontSize: 16,
    fontWeight: '500',
    color: '#111827',
  },
  signUpContainer: {
    alignItems: 'center',
    marginTop: 32,
    paddingBottom: 32,
  },
  signUpText: {
    fontSize: 16,
    color: '#6b7280',
  },
  signUpLink: {
    color: '#111827',
    fontWeight: '600',
  },
  errorContainer: {
    backgroundColor: '#fee2e2',
    borderColor: '#154733',
    borderWidth: 1,
    borderRadius: 8,
    padding: 12,
    marginBottom: 20,
  },
  errorText: {
    color: '#154733',
    fontSize: 14,
    textAlign: 'center',
  },
});
