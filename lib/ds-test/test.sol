pragma solidity 0.5.17;

contract DSTest {
    event log(string);
    event log_address(address);
    event log_bytes(bytes);
    event log_bytes32(bytes32);
    event log_int(uint);
    event log_uint(uint);
    event log_bool(bool);
    event log_named_address(string key, address val);
    event log_named_bytes(string key, bytes val);
    event log_named_bytes32(string key, bytes32 val);
    event log_named_decimal_int(string key, int val, uint decimals);
    event log_named_decimal_uint(string key, uint val, uint decimals);
    event log_named_int(string key, int val);
    event log_named_uint(string key, uint val);
    event log_named_string(string key, string val);

    bool private IS_TEST = true;

    function fail() internal pure {
        require(false, "test failed");
    }

    function assertTrue(bool condition) internal pure {
        require(condition, "assertTrue failed");
    }

    function assertEq(uint a, uint b) internal pure {
        require(a == b, "assertEq(uint) failed");
    }

    function assertEq(address a, address b) internal pure {
        require(a == b, "assertEq(address) failed");
    }

    function assertEq(bool a, bool b) internal pure {
        require(a == b, "assertEq(bool) failed");
    }
}
