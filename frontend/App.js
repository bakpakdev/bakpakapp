import React, { useState, useEffect } from 'react';
import { Animated, View, Text, TouchableOpacity, Easing } from 'react-native';
import { NavigationContainer, useNavigation } from '@react-navigation/native';
import { createStackNavigator } from '@react-navigation/stack';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { Provider as PaperProvider } from 'react-native-paper';
import { Ionicons } from '@expo/vector-icons';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { AuthContext } from './src/context/AuthContext';
import { useFonts, Poppins_400Regular, Poppins_500Medium, Poppins_700Bold } from '@expo-google-fonts/poppins';

// Screens
import LoginScreen from './src/screens/LoginScreen';
import RegisterScreen from './src/screens/RegisterScreen';
import HomeScreen from './src/screens/HomeScreen';
import SearchScreen from './src/screens/SearchScreen';
import CreateListingScreen from './src/screens/CreateListingScreen';
import EditListingScreen from './src/screens/EditListingScreen';
import ProfileScreen from './src/screens/ProfileScreen';
import ProductDetailScreen from './src/screens/ProductDetailScreen';
import UserProfileScreen from './src/screens/UserProfileScreen';
import MessagesScreen from './src/screens/MessagesScreen';
import ConversationScreen from './src/screens/ConversationScreen';
import SavedItemsScreen from './src/screens/SavedItemsScreen';
import LikedItemsScreen from './src/screens/LikedItemsScreen';
import OrdersScreen from './src/screens/OrdersScreen';
import CheckoutScreen from './src/screens/CheckoutScreen';
import CartScreen from './src/screens/CartScreen';
import MyListingsScreen from './src/screens/MyListingsScreen';
import EditProfileScreen from './src/screens/EditProfileScreen';

import { api } from './src/services/api';
import withFadeTransition from './src/components/withFadeTransition';

const Stack = createStackNavigator();
const Tab = createBottomTabNavigator();

// Fade transition configuration for smooth transitions
const fadeTransitionConfig = {
  transitionSpec: {
    open: {
      animation: 'timing',
      config: {
        duration: 350, // Smooth fade - 350ms
        easing: Easing.out(Easing.ease),
      },
    },
    close: {
      animation: 'timing',
      config: {
        duration: 350,
        easing: Easing.out(Easing.ease),
      },
    },
  },
  cardStyleInterpolator: ({ current }) => ({
    cardStyle: {
      opacity: current.progress,
    },
  }),
};

// Slide-up transition configuration for Create screen
const slideUpTransitionConfig = {
  gestureDirection: 'vertical',
  gestureEnabled: true,
  transitionSpec: {
    open: {
      animation: 'timing',
      config: {
        duration: 300,
      },
    },
    close: {
      animation: 'timing',
      config: {
        duration: 300,
      },
    },
  },
  cardStyleInterpolator: ({ current, layouts }) => {
    return {
      cardStyle: {
        transform: [
          {
            translateY: current.progress.interpolate({
              inputRange: [0, 1],
              outputRange: [layouts.screen.height, 0],
            }),
          },
        ],
      },
    };
  },
};

// Apply fade transitions to tab screens
const FadeHomeScreen = withFadeTransition(HomeScreen);
const FadeSearchScreen = withFadeTransition(SearchScreen);
const FadeMessagesScreen = withFadeTransition(MessagesScreen);
const FadeProfileScreen = withFadeTransition(ProfileScreen);

function HomeTabs() {
  const parentNavigation = useNavigation();
  
  return (
    <Tab.Navigator
      screenOptions={({ route }) => ({
        tabBarIcon: ({ focused, color, size }) => {
          let iconName;

          if (route.name === 'Home') {
            iconName = focused ? 'home' : 'home-outline';
          } else if (route.name === 'Search') {
            iconName = focused ? 'search' : 'search-outline';
          } else if (route.name === 'Create') {
            iconName = 'add';
          } else if (route.name === 'Messages') {
            iconName = focused ? 'chatbubbles' : 'chatbubbles-outline';
          } else if (route.name === 'Profile') {
            iconName = focused ? 'person' : 'person-outline';
          }

          return <Ionicons name={iconName} size={size} color={color} />;
        },
        tabBarLabelStyle: {
          fontSize: 12,
          fontWeight: '500',
          marginTop: 4,
        },
        tabBarActiveTintColor: '#111827',
        tabBarInactiveTintColor: '#9ca3af',
        headerShown: false,
        animationEnabled: true,
        tabBarStyle: {
          backgroundColor: '#fff',
          borderTopWidth: 1,
          borderTopColor: '#e5e7eb',
          height: 70,
          paddingBottom: 8,
          paddingTop: 8,
        },
        tabBarItemStyle: {
          paddingVertical: 4,
        },
      })}
    >
      <Tab.Screen 
        name="Home" 
        component={FadeHomeScreen}
        options={{
          tabBarLabel: 'Home',
          tabBarStyle: { display: 'flex' },
        }}
      />
      <Tab.Screen 
        name="Search" 
        component={FadeSearchScreen}
        options={{
          tabBarLabel: 'Search',
          tabBarStyle: { display: 'flex' },
        }}
      />
      <Tab.Screen 
        name="Create" 
        component={View}
        options={{
          tabBarLabel: 'Sell',
          tabBarStyle: { display: 'flex' },
          tabBarButton: (props) => (
            <TouchableOpacity
              {...props}
              style={{
                flex: 1,
                alignItems: 'center',
                justifyContent: 'center',
                marginTop: -12,
              }}
              onPress={() => {
                parentNavigation.navigate('CreateListing');
              }}
              activeOpacity={0.8}
            >
              <View style={{
                width: 50,
                height: 50,
                borderRadius: 25,
                backgroundColor: '#154733',
                alignItems: 'center',
                justifyContent: 'center',
                shadowColor: '#000',
                shadowOffset: { width: 0, height: 2 },
                shadowOpacity: 0.25,
                shadowRadius: 4,
                elevation: 5,
              }}>
                <Ionicons name="add" size={24} color="#fff" />
              </View>
              <Text style={{
                fontSize: 12,
                fontWeight: '500',
                color: '#111827',
                marginTop: 2,
              }}>
                Sell
              </Text>
            </TouchableOpacity>
          ),
        }}
      />
      <Tab.Screen 
        name="Messages" 
        component={FadeMessagesScreen}
        options={{
          tabBarLabel: 'Inbox',
          tabBarStyle: { display: 'flex' },
        }}
      />
      <Tab.Screen 
        name="Profile" 
        component={FadeProfileScreen}
        options={{
          tabBarLabel: 'Profile',
          tabBarStyle: { display: 'flex' },
        }}
      />
    </Tab.Navigator>
  );
}

export default function App() {
  const [user, setUser] = useState(null);
  const [loading, setLoading] = useState(true);
  const [fontsLoaded] = useFonts({
    Poppins_400Regular,
    Poppins_500Medium,
    Poppins_700Bold,
  });

  // Apply global default font for all React Native <Text> components
  useEffect(() => {
    if (fontsLoaded && Text) {
      // Preserve existing defaultProps.style if present
      Text.defaultProps = Text.defaultProps || {};
      const previousStyle = Text.defaultProps.style || {};
      Text.defaultProps.style = Array.isArray(previousStyle)
        ? [...previousStyle, { fontFamily: 'Poppins_400Regular' }]
        : [previousStyle, { fontFamily: 'Poppins_400Regular' }];
    }
  }, [fontsLoaded]);

  useEffect(() => {
    checkAuth();
  }, []);

  const checkAuth = async () => {
    try {
      const token = await AsyncStorage.getItem('token');
      if (token) {
        api.defaults.headers.common['Authorization'] = `Bearer ${token}`;
        const response = await api.get('/auth/me');
        setUser(response.data);
      }
    } catch (error) {
      console.error('Auth check error:', error);
      await AsyncStorage.removeItem('token');
    } finally {
      setLoading(false);
    }
  };

  const login = async (token, userData) => {
    await AsyncStorage.setItem('token', token);
    api.defaults.headers.common['Authorization'] = `Bearer ${token}`;
    setUser(userData);
  };

  const logout = async () => {
    await AsyncStorage.removeItem('token');
    delete api.defaults.headers.common['Authorization'];
    setUser(null);
  };

  if (!fontsLoaded || loading) {
    return (
      <PaperProvider>
        <View style={{ flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: '#fff' }}>
          <Text style={{ fontFamily: fontsLoaded ? 'Poppins_400Regular' : undefined }}>Loading...</Text>
        </View>
      </PaperProvider>
    );
  }

  return (
    <PaperProvider>
      <AuthContext.Provider value={{ user, login, logout }}>
        <NavigationContainer key={user ? 'authenticated' : 'unauthenticated'}>
          <Stack.Navigator 
            screenOptions={{ 
              headerShown: false,
              ...fadeTransitionConfig,
            }}
          >
            {user ? (
              <>
                <Stack.Screen name="MainTabs" component={HomeTabs} />
                <Stack.Screen 
                  name="CreateListing" 
                  component={CreateListingScreen}
                  options={slideUpTransitionConfig}
                />
                <Stack.Screen 
                  name="EditListing" 
                  component={EditListingScreen}
                  options={slideUpTransitionConfig}
                />
                <Stack.Screen 
                  name="ProductDetail" 
                  component={ProductDetailScreen}
                  options={fadeTransitionConfig}
                />
                <Stack.Screen 
                  name="UserProfile" 
                  component={UserProfileScreen}
                  options={fadeTransitionConfig}
                />
                <Stack.Screen 
                  name="Conversation" 
                  component={ConversationScreen}
                  options={fadeTransitionConfig}
                />
                <Stack.Screen 
                  name="SavedItems" 
                  component={SavedItemsScreen}
                  options={fadeTransitionConfig}
                />
                <Stack.Screen 
                  name="LikedItems" 
                  component={LikedItemsScreen}
                  options={fadeTransitionConfig}
                />
                <Stack.Screen 
                  name="Orders" 
                  component={OrdersScreen}
                  options={fadeTransitionConfig}
                />
                <Stack.Screen 
                  name="Cart" 
                  component={CartScreen}
                  options={fadeTransitionConfig}
                />
                <Stack.Screen 
                  name="Checkout" 
                  component={CheckoutScreen}
                  options={fadeTransitionConfig}
                />
                <Stack.Screen 
                  name="MyListings" 
                  component={MyListingsScreen}
                  options={fadeTransitionConfig}
                />
                <Stack.Screen 
                  name="EditProfile" 
                  component={EditProfileScreen}
                  options={fadeTransitionConfig}
                />
              </>
            ) : (
              <>
                <Stack.Screen 
                  name="Login" 
                  component={LoginScreen}
                  options={fadeTransitionConfig}
                />
                <Stack.Screen 
                  name="Register" 
                  component={RegisterScreen}
                  options={fadeTransitionConfig}
                />
              </>
            )}
          </Stack.Navigator>
        </NavigationContainer>
      </AuthContext.Provider>
    </PaperProvider>
  );
}

