##Summary

The delegateToImplementation function in the MErc20Delegator contract(Smart Contract - Moonwell ETH) is publicly accessible (its ABI shows no access control).
Because delegatecall executes the implementation code using the delegator’s storage context, a non-admin caller can trigger arbitrary functions from the implementation that modify the delegator’s storage.

If the implementation contains initialization or sensitive functions (such as _becomeImplementation, mint, or other state-mutating logic), an attacker can exploit this to take over admin privileges, mint tokens, drain assets, or brick the contract.

##Scope
MErc20Delegator contract(Smart Contract - Moonwell ETH)

MErc20Delegator.sol code:
![PoC Diagram](images/code-code-MErc20Delegator.png)
![PoC Diagram](images/code-code-MErc20Delegator-2.png)

##Root Cause:
Lack of access control (onlyAdmin) on delegateToImplementation.

The implementation acts as the execution target, exposing critical functionality such as transfer, transferFrom, mint, etc., without restrictions.

##Proof of Concept
(test/DelegateAccess.t.sol) code :


![PoC Diagram](images/code-DelegateAccess.png)
![PoC Diagram](images/code-DelegateAccess-2.png)


Teset Result

![PoC Diagram](images/result-DelegateAccess.png)


Expected behavior: both calls should revert.
Actual behavior: no revert occurred, proving public accessibility.

This confirms that delegateToImplementation and delegateToViewImplementation are callable by anyone.

Exploit Simulation
test/MintPoC.t.sol code:

![PoC Diagram](images/code-MintPoC.png)
![PoC Diagram](images/code-MintPoC-2.png)


result

![PoC Diagram](images/result-MintPoC.png)


The attacker successfully minted tokens without reducing their underlying balance — confirming unrestricted delegatecall execution.

##Impact

Because delegateToImplementation(bytes) is publicly callable, an attacker can:

Execute arbitrary implementation functions in the delegator’s storage context.

Bypass admin-only restrictions.

Mint unlimited tokens or drain protocol funds.

Take over admin privileges or brick the contract permanently.

This vulnerability completely compromises the protocol’s trust model.

Recommendation

Restrict delegateToImplementation and delegateToViewImplementation with proper access control.

![PoC Diagram](images/Recommendation.png)

