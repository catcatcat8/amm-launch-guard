import { ethers } from 'hardhat'

import type { AntiSync, Token } from '@/typechain'
import { Router__factory, Factory__factory } from '../typechain-pancake'

const BSC_ROUTER_ADDR = "0x10ED43C718714eb63d5aA57B78B54704E256024E"
const BSC_FACTORY_ADDR = "0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73"

export const BSC_BUSD = "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56"
export const BSC_BUSD_HOLDER = "0x54026021038f2084e3A0a27760D3923286BDAdb0"

export const useContracts = async () => {
  return {
    token: await ethers.getContract<Token>('Token'),
    antiSync: await ethers.getContract<AntiSync>('AntiSync'),
    router: await Router__factory.connect(BSC_ROUTER_ADDR, ethers.provider),
    factory: await Factory__factory.connect(BSC_FACTORY_ADDR, ethers.provider)
  }
}
