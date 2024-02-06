object "ERC1155" {
  // Constructor
  code {
    // Look at the runtime code and copy it to memory
    datacopy(0, dataoffset("Runtime"), datasize("Runtime"))
    // Return that area of memory
    return(0, datasize("Runtime"))
  }

  object "Runtime" {
    code {
      // Extract the called function by getting the first 4 bytes of calldata
      // Shift right by 224 bits (28 bytes)
      let selector := shr(0xe0, calldataload(0x00))
      // Dispatcher
      switch selector

      // External functions
      case 0x731133e9 /* "mint(address,uint256,uint256,bytes)" */ {
          // TODO add only owner check?

          // mint to, id, amount, data
          mint(decodeAsAddress(0), decodeAsUint(1), decodeAsUint(2), decodeAsBytes(3))
          returnEmpty()
      }

      // View functions
      case 0x00fdd58e /* "balanceOf(address,uint256)" */ {
          returnUint(balanceOf(decodeAsAddress(0), decodeAsUint(1)))
      }



      //? Is this an internal function? Yes because it's not in the dispatcher
      function mint(to, id, amount, _data) {
          // Check that it is not to address(0)
          notZeroAddress(to)
          // Add to balanceOf, checking for overflow
          addBalanceOf(to, id, amount)
          // Emit Transfer event
          emitTransferSingle(0x00, to, id, amount, _data)
          // If the recipient is a contract, we call onERC1155Received

          // // Check if recipient is a contract by code length > 0
          // if isContract(to) {
          //     // Call to with onERC1155Received and expect return data to be onERC1155Received.selector
          //     // 0xf23a6e61 is the selector for onERC1155Received(address,address,uint256,uint256,bytes)
          //     // opcode CALL (gas, address, value, argOffset, argSize, retOffset, retSize)
          //     to.call(0xf23a6e61,)
          //     // If not then revert the transaction
          // }
      }

      /* --- storage layout --- */

      function balanceOfSlot() -> slot { slot := 0 }
      function allowanceSlot() -> slot { slot := 1 }


      /* --- storage access functions --- */

      function addBalanceOf(to, id, amount) {
          // Get current position
          let valuePos := getNestedMappingValuePos(balanceOfSlot(), to, id)
          // Set new value, checking for overflow
          sstore(valuePos, safeAdd(sload(valuePos), amount))
      }

      // owner => id => balance
      // mapping(address => mapping(uint256 => uint256)) public balanceOf;
      function balanceOf(addr, id) -> u {
          u := sload(getNestedMappingValuePos(balanceOfSlot(), addr, id))
      }

      function getMappingValuePos(slot, key) -> pos {
          // We assume here key is a value type
          // We can get a mapping value position in storage by doing keccak256(valueTypeKey.concat(mappingSlot))
          mstore(0x00, key)
          mstore(0x20, slot)
          pos := keccak256(0x00, 0x40)
      }

      function getNestedMappingValuePos(slot, firstKey, secondKey) -> pos {
          // We assume here keys are value types
          // We can get a nested mapping value position in storage by doing keccak256(valueTypeSecondKey.concat(keccak256(valueTypeFirstKey.concat(mappingSlot))))
          pos := getMappingValuePos(
              getMappingValuePos(slot, firstKey),
              secondKey
          )
      }



      /* --- calldata decoding/sanitization functions --- */

      function decodeAsUint(offset) -> u {
          // Calldata arg starts at offset * 32 bytes + 4 sig bytes
          let pos := add(0x04, mul(offset, 0x20))
          // We don't trust the input data
          // We check we can read 32 bytes in the calldata
          require(iszero(lt(calldatasize(), add(pos, 0x20))))
          u := calldataload(pos)
      }

      function decodeAsAddress(offset) -> a {
          a := decodeAsUint(offset)
          // We don't trust the input data
          // We check a is a valid uint160 value
          require(lt(a, 0xffffffffffffffffffffffffffffffffffffffff))
      }

      function decodeAsBytes(offset) -> b {
          let pos := add(0x04, mul(offset, 0x20))
          // TODO check if any validation necessary
          b := calldataload(pos)
      }

      /* --- calldata encoding functions --- */

      function returnEmpty() {
          return(0x00, 0x00)
      }

      function returnUint(u) {
          mstore(0x00, u)
          return(0x00, 0x20)
      }

      function returnTrue() {
          returnUint(0x01)
      }

      function returnAddress(addr) {
          returnUint(addr)
      }

      /* --- utility functions --- */

      function safeAdd(a, b) -> c {
          c := add(a, b)
          // Check overflow
          // if c < a, then lt will return 1, then iszero will return 0, then require will revert
          require(iszero(lt(c, a)))
      }

      function safeSub(a, b) -> c {
          c := sub(a, b)
          // Check underflow
          require(iszero(gt(c, a)))
      }

      // function calledByOwner() -> c {
      //     c := eq(caller(), owner())
      //     // TODO why no need for require?
      // }

      function require(condition) {
          if iszero(condition) { revert(0x00, 0x00) }
      }

      function notZeroAddress(a) {
        // if address is zero, then eq will return 1, then iszero will return 0, then require will revert
        let c := eq(a, 0x0000000000000000000000000000000000000000)
        require(iszero(c))
      }

      function isContract(a) -> c {
          c := gt(extcodesize(a), 0)
      }

      /* --- external call functions --- */
      function externalViewCallNoArgs(a, s) -> r {
          // Do we need to load selector into memory?

          // Get location of free memory pointer
          let x:= mload(0x40)
          // Store selector at free memory pointer
          mstore(x, s)

          let success := staticcall(
            gas(),
            a, // to
            0, // no input
            x, // Inputs stored at location x
            x, // Write output over input (saves space?)
            0x20 // Output size
          )

          if iszero(success) {
              revert(0x00, 0x00)
          }

          r := mload(x)
      }

      /* --- events functions --- */

      // address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value
      function emitTransferSingle(operator, from, to, id, value) {
          // To log an event we must abi.encode the non indexed args in the data entry
          // In t1 we push the event.
          // Then add the bytes32 value or keccak256 hash of each indexed arg in a topic
          //
          // example: emit Transfer(address indexed from, address indexed to, uint256 value)
          // data: value in memory
          // t1: keccak256("Transfer(address,address,uint256)")
          // t2: from
          // t3: to
          mstore(0x00, id)
          mstore(0x20, value)
          log4(
              0x00, // Memory location where non-indexed args are stored
              0x40,
              0xc3d58168c5ae7397731d063d5bbf3d657854427343f4c083240f7aacaa2d0f62 /* "TransferSingle(address,address,address,uint256,uint256)" */,
              operator, // indexed arg
              from, // indexed arg
              to // indexed arg
          )
      }





    }
  }
}
