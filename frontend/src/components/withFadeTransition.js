import React, { useEffect, useRef } from 'react';
import { Animated, Platform, Easing } from 'react-native';
import { useIsFocused } from '@react-navigation/native';

export default function withFadeTransition(Component) {
  return function FadeTransitionWrapper(props) {
    const isFocused = useIsFocused();
    const fadeAnim = useRef(new Animated.Value(0)).current;
    const previousFocused = useRef(false);

    useEffect(() => {
      // Always animate when focus changes, including first click
      if (isFocused) {
        // Fade in when becoming focused
        fadeAnim.setValue(0);
        Animated.timing(fadeAnim, {
          toValue: 1,
          duration: 350, // Smooth fade - 350ms
          easing: Easing.out(Easing.ease), // Smooth easing curve
          useNativeDriver: Platform.OS !== 'web', // Disable for web to avoid warning
        }).start();
      } else if (previousFocused.current) {
        // Fade out when losing focus
        Animated.timing(fadeAnim, {
          toValue: 0,
          duration: 350,
          easing: Easing.out(Easing.ease),
          useNativeDriver: Platform.OS !== 'web',
        }).start();
      }
      previousFocused.current = isFocused;
    }, [isFocused, fadeAnim]);

    return (
      <Animated.View style={{ flex: 1, opacity: fadeAnim }}>
        <Component {...props} />
      </Animated.View>
    );
  };
}

