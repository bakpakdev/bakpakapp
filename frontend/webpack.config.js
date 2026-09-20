const createExpoWebpackConfigAsync = require('@expo/webpack-config');

module.exports = async function (env, argv) {
  const config = await createExpoWebpackConfigAsync(env, argv);

  // Ensure CSS imports work on web (Tailwind via PostCSS).
  config.module.rules.push({
    test: /\.css$/i,
    use: [
      require.resolve('style-loader'),
      {
        loader: require.resolve('css-loader'),
        options: { importLoaders: 1 },
      },
      require.resolve('postcss-loader'),
    ],
  });

  return config;
};

