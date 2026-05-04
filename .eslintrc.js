module.exports = {
  root: true,
  extends: '@react-native',
  overrides: [
    {
      files: ['*.mjs', '**/*.mjs'],
      parserOptions: {
        ecmaVersion: 'latest',
        sourceType: 'module',
      },
    },
  ],
};
