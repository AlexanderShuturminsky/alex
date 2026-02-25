const { createDefaultPreset } = require("ts-jest");

const tsJestTransformCfg = createDefaultPreset({
  tsconfig: "tsconfig.jest.json",
}).transform;

/** @type {import("jest").Config} **/
module.exports = {
  testEnvironment: "jsdom",
  transform: {
    ...tsJestTransformCfg,
  },
  setupFilesAfterEnv: ["@testing-library/jest-dom"],
};
