// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "../src/contracts/core/StrategyManager.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "forge-std/Script.sol";
import "forge-std/Test.sol";

contract Upgrade_SM_Test is Script, Test {
    StrategyManager public newStrategyManager;
    ProxyAdmin public proxyAdmin;

    function run() external {
        vm.startBroadcast();

        // Deploy New DelegationManager
        newStrategyManager = new StrategyManager(
            IDelegationManager(0x45b4c4DAE69393f62e1d14C5fe375792DF4E6332),
            IEigenPodManager(0x33e42d539abFe9b387B27b0e467374Bbb76cf925),
            ISlasher(0xF751E8C37ACd3AD5a35D5db03E57dB6F9AD0bDd0)
        );

        // Upgrade Proxy Contract
        proxyAdmin = ProxyAdmin(payable(0x555573Ff2B3b2731e69eeBAfb40a4EEA7fBaC54A));
        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(0xD309ADd2B269d522112DcEe0dCf0b0f04a09C29e)),
            address(newStrategyManager)
        );

        vm.stopBroadcast();
    }
}