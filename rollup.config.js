// import resolve from 'rollup-plugin-node-resolve'

export default {
  input: 'dist/stimulus-bind.es',
  output: {
    name: 'StimulusBind',
    format: 'umd',
    file: 'dist/stimulus-bind.umd.js',
    globals: {
      stimulus: 'Stimulus',
      jsep: 'jsep'
    }
  },
  // plugins: [resolve({})],
  external: ['stimulus', 'jsep']
}
