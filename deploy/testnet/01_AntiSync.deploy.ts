import { ethers } from 'hardhat'
import type { DeployFunction } from 'hardhat-deploy/types'

import { AntiSync__factory } from '@/typechain'
import { wrapperHRE } from '@gotbit/evm-hardhat'

const func: DeployFunction = async (hre) => {
  const { deploy } = wrapperHRE(hre)
  const [deployer] = await ethers.getSigners()

  await deploy<AntiSync__factory>('AntiSync', {
    from: deployer.address,
    args: [deployer.address],
    log: true,
  })
}
export default func

func.tags = ['AntiSync.deploy']
