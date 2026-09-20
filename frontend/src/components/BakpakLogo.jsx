import React from 'react';
import Svg, { Path, Text } from 'react-native-svg';

export default function PopupLogo({ size = 120, color = '#000' }) {
  return (
    <Svg width={size} height={size} viewBox="0 0 120 120" fill="none">
      {/* Backpack body - soft rounded rectangle */}
      <Path
        d="M20 28 C20 20, 25 15, 33 15 L87 15 C95 15, 100 20, 100 28 L100 82 C100 90, 95 95, 87 95 L33 95 C25 95, 20 90, 20 82 Z"
        fill={color}
        stroke={color}
        strokeWidth={2}
        strokeLinejoin="round"
      />
      
      {/* Handle at the top - small rounded handle */}
      <Path
        d="M48 15 Q60 12, 72 15"
        stroke="#fff"
        strokeWidth={2.5}
        strokeLinecap="round"
        fill="none"
      />
      
      {/* "bp" text - bold, centered, lowercase, integrated */}
      <Text
        x="60"
        y="70"
        fontSize="44"
        fontWeight="bold"
        fill="#fff"
        textAnchor="middle"
        fontFamily="Arial, sans-serif"
        letterSpacing={-2}
      >
        bp
      </Text>
    </Svg>
  );
}

