// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.5.17;

import "../lib/ds-test/test.sol";
import "../src/MErc20Delegator.sol";
import "../src/InterestRateModel.sol";

// ---- Dummy Comptroller untuk test ----
contract DummyComptroller {
    bool public constant isComptroller = true;
}

// ---- Dummy InterestRateModel ----
contract DummyIRM is InterestRateModel {
    function getBorrowRate(uint, uint, uint) external view returns (uint) {
        return 0;
    }

    function getSupplyRate(uint, uint, uint, uint) external view returns (uint) {
        return 0;
    }
}


// ---- Attacker contract for simulationl ----
contract Attacker {
    function callDelegateToImpl(address delegator, bytes memory payload)
        public
        returns (bool, bytes memory)
    {
        (bool ok, bytes memory ret) =
            delegator.call(abi.encodeWithSignature("delegateToImplementation(bytes)", payload));
        return (ok, ret);
    }

    function callDelegateToViewImpl(address delegator, bytes memory payload)
        public
        returns (bool, bytes memory)
    {
        (bool ok, bytes memory ret) =
            delegator.call(abi.encodeWithSignature("delegateToViewImplementation(bytes)", payload));
        return (ok, ret);
    }
}

// ---- Test utama ----
contract DelegateAccessTest is DSTest {
    MErc20Delegator delegator;
    DummyComptroller comptroller;
    DummyIRM irm;
    Attacker attacker;

    function setUp() public {
        comptroller = new DummyComptroller();
        irm = new DummyIRM();
        attacker = new Attacker();

        // Deploy dummy delegator sesuai struktur aslinya
        delegator = new MErc20Delegator(
            address(0x1234567890000000000000000000000000000000), // underlying dummy
            ComptrollerInterface(address(comptroller)),
            InterestRateModel(address(irm)),
            1e18, // initialExchangeRateMantissa
            "SecToken",
            "STK",
            18,
            address(uint160(address(this))), // admin = test contract
            address(0x1234567890000000000000000000000000000000), // dummy implementation
            "" // empty becomeImplementationData
        );
    }

    // --------- Tests ----------

    // Must revert if attacker tries to delegate directly
function test_attacker_cannot_call_delegateToImplementation() public {
    bytes memory payload = abi.encodeWithSignature("_becomeImplementation(bytes)", "");
    (bool ok, ) = attacker.callDelegateToImpl(address(delegator), payload);
    // Expect call to revert/return false
    assertTrue(!ok);
}

function test_attacker_cannot_call_delegateToViewImplementation() public {
    bytes memory payload = abi.encodeWithSignature("totalBorrows()");
    (bool ok, ) = attacker.callDelegateToViewImpl(address(delegator), payload);
    assertTrue(!ok);
}

}
