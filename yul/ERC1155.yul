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
          mint(decodeAsAddress(0), decodeAsUint(1), decodeAsUint(2), decodeAsUint(3))
          returnEmpty()
      }

      // View functions
      case 0x00fdd58e /* "balanceOf(address,uint256)" */ {
          returnUint(balanceOf(decodeAsAddress(0), decodeAsUint(1)))
      }

      //? Is this an internal function? Yes because it's not in the dispatcher
      function mint(to, id, amount, dataOffset) {
          // Check that it is not to address(0)
          notZeroAddress(to)
          // Add to balanceOf, checking for overflow
          addBalanceOf(to, id, amount)
          // Emit Transfer event
          emitTransferSingle(caller(), 0x0, to, id, amount)
          // If the recipient is a contract, we call onERC1155Received
          _doSafeTransferAcceptanceCheck(caller(), 0x0, to, id, amount)
      }


      /* --- safe transfer --- */

      function _doSafeTransferAcceptanceCheck(operator, from, to, id, amount) {
          if isContract(to) {
              let onERC1155ReceivedSelector := 0xf23a6e6100000000000000000000000000000000000000000000000000000000

              let dataOffset := calldataload(0x64) // would return 0x80 (4th word of calldata)
              let dataStartPos := add(dataOffset, 0x04) // need to add 0x04 to skip the selector

              mstore(0, onERC1155ReceivedSelector)
              mstore(0x04, operator)
              mstore(0x24, from)
              mstore(0x44, id)
              mstore(0x64, amount)
              // store bytes starting position - 0xa0 = 5th word?
              mstore(0x84, 0xa0)
              // calldatacopy(destOffset, offset, size) ; 0xa4 is the next area in memory to write to
              calldatacopy(0xa4, dataStartPos, sub(calldatasize(), dataStartPos))

              let success := call(
                  gas(),
                  to,
                  0, // value
                  0, // argOffset
                  add(calldatasize(), 0x20), // for additional operator arg
                  0x00, // retOffset
                  0x04 // retSize
              )

              if iszero(success) {
                  revert(0x00, 0x00)
              }

              // Require return data to be equal to onERC1155Received.selector (0xf23a6e61)
              returndatacopy(0x00, 0x00, 0x20)
              require(eq(mload(0x00), onERC1155ReceivedSelector))
          }
      }

      // 2nd version of _doSafeTransferAcceptanceCheck
      // function _doSafeTransferAcceptanceCheck(operator, from, to, id, amount) {
      //     if isContract(to) {
      //         let onERC1155ReceivedSelector := 0xf23a6e61
      //         let dataOffset := calldataload(0x64)
      //         let dataStartPos := add(dataOffset, 0x04)

      //         // let memPtr := mload(0x40)
      //         mstore(0, onERC1155ReceivedSelector) // pads left with zeroes
      //         mstore(0x20, operator)
      //         mstore(0x40, from)
      //         mstore(0x60, id)
      //         mstore(0x80, amount)
      //         mstore(0xa0, 0xa0)

      //         calldatacopy(0xc0, dataStartPos, sub(calldatasize(), dataStartPos))

      //         let success := call(
      //             gas(),
      //             to,
      //             0, // value
      //             28, // argOffset
      //             add(calldatasize(), 0x20), // argSize
      //             0x00, // retOffset
      //             0x04 // retSize
      //         )

      //         if iszero(success) {
      //             revert(0x00, 0x00)
      //         }

      //         // Require return data to be equal to onERC1155Received.selector (0xf23a6e61)
      //         returndatacopy(0x00, 0x00, 0x20)
      //         require(eq(mload(0x00), 0xf23a6e6100000000000000000000000000000000000000000000000000000000))
      //     }
      // }

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