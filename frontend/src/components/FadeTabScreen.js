import React, { useEffect, useRef } from 'react';
import { Animated } from 'react-native';

export default function FadeTabScreen({ children, isFocused }) {
  const fadeAnim = useRef(new Animated.Value(isFocused ? 1 : 0)).current;

  useEffect(() => {
    Animated.timing(fadeAnim, {
      toValue: isFocused ? 1 : 0,
      duration: 200, // Very quick fade - 200ms
      useNativeDriver: true,
    }).start();
  }, [isFocused, fadeAnim]);

  return (
    <Animated.View
      style={{
        flex: 1,
        opacity: fadeAnim,
      }}
    >
      {children}
    </Animated.View>
  );
}

