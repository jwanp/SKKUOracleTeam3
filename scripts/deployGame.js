// global scope, and execute the script.
const {ethers} = require("hardhat");

async function main() {
  const  [deployer] = await ethers.getSigners();

  const PredictGame = await ethers.deployContract("PredictGame");
  await PredictGame.waitForDeployment();

  console.log("PredictGame deployed to:", PredictGame.target);
  console.log("Deployer address:", deployer.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
