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
          _mint(decodeAsAddress(0), decodeAsUint(1), decodeAsUint(2), decodeAsUint(3))
          returnEmpty()
      }

      case 0xb48ab8b6 /* "batchMint(address,uint[],uint[],bytes)" */ {
          _batchMint()
          returnEmpty()
      }

      // case 0xb390c0ab /* "burn(uint256,uint256)" */ {
      //     // burn msg.sender, id, amount
      //     _burn(caller(), decodeAsUint(0), decodeAsUint(1))
      //     returnEmpty()
      // }

      case 0xf5298aca /* "burn(address,uint256,uint256)" */ {
          // burn from, id, amount
          _burn(decodeAsAddress(0), decodeAsUint(1), decodeAsUint(2))
          returnEmpty()
      }

      case 0xf242432a /* "safeTransferFrom(address,address,uint,uint,bytes)" */ {
          _safeTransferFrom(decodeAsAddress(0), decodeAsAddress(1), decodeAsUint(2), decodeAsUint(3), decodeAsUint(4))
          returnEmpty()
      }

      // View functions
      case 0x00fdd58e /* "balanceOf(address,uint256)" */ {
          returnUint(balanceOf(decodeAsAddress(0), decodeAsUint(1)))
      }

      // Internal functions

      function _safeTransferFrom(from, to, id, amount, dataOffset) {
          // Check that caller is msg.sender or is approved for all
          requireOr(eq(caller(), from), isApprovedForAll(from, caller()))
          // Check that it is not to address(0)
          notZeroAddress(to)
          // Sub from balanceOf, checking for underflow
          subBalanceOf(from, id, amount)
          // Add to balanceOf, checking for overflow
          addBalanceOf(to, id, amount)
          // Emit Transfer event
          emitTransferSingle(caller(), from, to, id, amount)
          // If the recipient is a contract, we call onERC1155Received
          _doSafeTransferAcceptanceCheck(caller(), from, to, id, amount, dataOffset)
      }

      function _mint(to, id, amount, dataOffset) {
          // Check that it is not to address(0)
          notZeroAddress(to)
          // Add to balanceOf, checking for overflow
          addBalanceOf(to, id, amount)
          // Emit Transfer event
          emitTransferSingle(caller(), 0x0, to, id, amount)
          // If the recipient is a contract, we call onERC1155Received
          _doSafeTransferAcceptanceCheck(caller(), 0x0, to, id, amount, dataOffset)
      }

      function _batchMint() {
          let to := decodeAsAddress(0)
          let idsOffset := decodeAsUint(1) // reads what's at calldata 0x24
          let amountsOffset := decodeAsUint(2)
          let dataOffset := decodeAsUint(3)

          let idsStartPos := add(idsOffset, 0x04)
          let idsLength := calldataload(idsStartPos)

          let amountsStartPos := add(amountsOffset, 0x04)
          let amountsLength := calldataload(amountsStartPos)

          let dataStartPos := add(dataOffset, 0x04)

          notZeroAddress(to)
          require(eq(idsLength, amountsLength))

          for { let i := 0 } lt(i, idsLength) { i := add(i, 0x01) } {
              addBalanceOf(
                to,
                calldataload(add(idsStartPos, mul(i, 0x20))),
                calldataload(add(amountsStartPos, mul(i, 0x20)))
              )
          }

          emitTransferBatch(caller(), 0x0, to)

          _doBatchSafeTransferAcceptanceCheck(caller(), 0x0, to, dataOffset, dataStartPos)
      }

      function _burn(from, id, amount) {
          // Check that it is not from address(0)
          notZeroAddress(from)
          // Need to check that the caller is the owner of the token? No need because non-existent token balance should underflow
          // Sub from balanceOf, checking for underflow
          subBalanceOf(from, id, amount)
          // Emit Transfer event
          emitTransferSingle(caller(), from, 0x0, id, amount)
      }

      function _doBatchSafeTransferAcceptanceCheck(operator, from, to, dataOffset, dataStartPos) {
          if isContract(to) {
              let onERC1155BatchReceivedSelector := 0xbc197c8100000000000000000000000000000000000000000000000000000000

              let idsAmountsLength := sub(calldatasize(), 0x24)

              mstore(0, onERC1155BatchReceivedSelector)
              mstore(0x04, operator)
              mstore(0x24, from)
              calldatacopy(0x44, 0x24, idsAmountsLength) // copy ids and amounts
              mstore(add(0x44, idsAmountsLength), dataOffset) // store bytes starting position
              calldatacopy(add(0x64, idsAmountsLength), dataStartPos, sub(calldatasize(), dataStartPos)) // copy data

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
              require(eq(mload(0x00), onERC1155BatchReceivedSelector))
          }
      }

      function _doSafeTransferAcceptanceCheck(operator, from, to, id, amount, dataOffset) {
          if isContract(to) {
              let onERC1155ReceivedSelector := 0xf23a6e6100000000000000000000000000000000000000000000000000000000

              // let dataOffset := calldataload(0x64) // would return 0x80 (4th word of calldata)
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

      function subBalanceOf(from, id, amount) {
          // Get current position
          let valuePos := getNestedMappingValuePos(balanceOfSlot(), from, id)
          // Set new value, checking for underflow
          sstore(valuePos, safeSub(sload(valuePos), amount))
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

      function isApprovedForAll(f, c) -> a {
          a := sload(getNestedMappingValuePos(allowanceSlot(), f, c))
      }

      function require(condition) {
          if iszero(condition) { revert(0x00, 0x00) }
      }

      function requireOr(condition1, condition2) {
          if iszero(condition1) {
             if iszero(condition2) {
               revert(0x00, 0x00)
             }
           }
      }

      function notZeroAddress(a) {
        // if address is zero, then eq will return 1, then iszero will return 0, then require will revert
        let c := eq(a, 0x0000000000000000000000000000000000000000)
        require(iszero(c))
      }

      function isContract(a) -> c {
          c := gt(extcodesize(a), 0)
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

      // calldatacopy(0xa4, dataStartPos, sub(calldatasize(), dataStartPos))

      //TODO test correct event emission
      function emitTransferBatch(operator, from, to) {
          // how to dynamically load calldata into memory? calldatacopy?
          calldatacopy(0x00, 0x24, sub(calldatasize(), 0x24)) // 0x24 to exclude selector and address arg

          log4(
              0x00, // Memory location where non-indexed args are stored
              sub(calldatasize(), 0x24),
              0x4a39dc06d4c0dbc64b70af90fd698a233a518aa5d07e595d983b8c0526c8f7fb /* keccak "TransferBatch(address,address,address,uint256[],uint256[])" */,
              operator, // indexed arg
              from, // indexed arg
              to // indexed arg
          )
      }





    }
  }
}
