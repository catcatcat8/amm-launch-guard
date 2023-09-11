import { ethers } from 'hardhat'
import type { DeployFunction } from 'hardhat-deploy/types'

import { Token__factory } from '@/typechain'
import { wrapperHRE } from '@gotbit/evm-hardhat'

const func: DeployFunction = async (hre) => {
  const { deploy } = wrapperHRE(hre)
  const [deployer] = await ethers.getSigners()

  await deploy<Token__factory>('Token', {
    from: deployer.address,
    args: ['Token', 'TKN', 1_000_000],
    log: true,
  })
}
export default func

func.tags = ['Token.deploy']
