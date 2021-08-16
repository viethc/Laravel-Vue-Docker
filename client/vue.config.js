const BundleAnalyzerPlugin =
  require('webpack-bundle-analyzer').BundleAnalyzerPlugin;

const plugins = [];

plugins.push(new BundleAnalyzerPlugin({ analyzerMode: 'disabled' }));

module.exports = {
  devServer: {
    proxy: {
      '^/api': {
        target: 'https://webserver/',
        ws: true,
        secure: false,
      },
    },
    port: 8081,
  },
  configureWebpack: {
    plugins,
  },
};
