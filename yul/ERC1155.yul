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

      case 0xf6eb127a /* "batchBurn(address,uint[],uint[])" */ {
          // burn from, ids, amounts
          _batchBurn()
          returnEmpty()
      }

      case 0xa22cb465 /* "setApprovalForAll(address,bool)" */ {
          // setApprovalForAll operator, approved
          sstore(getNestedMappingValuePos(allowanceSlot(), caller(), decodeAsAddress(0)), decodeAsUint(1))
          emitApprovalForAll(caller(), decodeAsAddress(0), decodeAsUint(1))
          returnEmpty()
      }

      case 0xf242432a /* "safeTransferFrom(address,address,uint,uint,bytes)" */ {
          _safeTransferFrom(decodeAsAddress(0), decodeAsAddress(1), decodeAsUint(2), decodeAsUint(3), decodeAsUint(4))
          returnEmpty()
      }

      case 0x2eb2c2d6 /* "safeBatchTransferFrom(address,address,uint[],uint[],bytes)" */ {
          // safeBatchTransferFrom(from, to, ids, amounts, data)
          _safeBatchTransferFrom()
          returnEmpty()
      }

      // View functions


      case 0x00fdd58e /* "balanceOf(address,uint256)" */ {
          returnUint(balanceOf(decodeAsAddress(0), decodeAsUint(1)))
      }

      case 0x4e1273f4 /* "balanceOfBatch(address[],uint[])" */ {
          // balanceOfBatch(addresses, ids)
          let addressesOffset := decodeAsUint(0)
          let idsOffset := decodeAsUint(1)

          let addressesStartPos := add(addressesOffset, 0x04)
          let addressesLength := calldataload(addressesStartPos)

          let idsStartPos := add(idsOffset, 0x04)
          let idsLength := calldataload(idsStartPos)

          require(eq(addressesLength, idsLength))

          let addressPos := addressesStartPos
          let idPos := idsStartPos

          mstore(0x100, 0x20) // store offset
          mstore(0x120, idsLength) // store length of return array
          let x := 0

          for { let i := 0 } lt(i, idsLength) { i := add(i, 0x01) } {
              addressPos := add(addressPos, 0x20)
              idPos := add(idPos, 0x20)
              x := balanceOf(calldataload(addressPos), calldataload(idPos))
              mstore(add(0x140, mul(i, 0x20)), x)
          }

          return(0x100, add(0x40, mul(idsLength, 0x20))) // return offset + len + elements
      }

      case 0xe985e9c5 /* "isApprovedForAll(address,address)" */ {
          returnUint(isApprovedForAll(decodeAsAddress(0), decodeAsAddress(1)))
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

      function _safeBatchTransferFrom() {
          let from := decodeAsAddress(0)
          let to := decodeAsAddress(1)
          let idsOffset := decodeAsUint(2)
          let amountsOffset := decodeAsUint(3)
          let dataOffset := decodeAsUint(4)

          let idsStartPos := add(idsOffset, 0x04)
          let idsLength := calldataload(idsStartPos)

          let amountsStartPos := add(amountsOffset, 0x04)
          let amountsLength := calldataload(amountsStartPos)

          let dataStartPos := add(dataOffset, 0x04)

          notZeroAddress(to)
          require(eq(idsLength, amountsLength))

          let idPos := idsStartPos
          let amountPos := amountsStartPos

          for { let i := 0 } lt(i, idsLength) { i := add(i, 0x01) } {
              idPos := add(idPos, 0x20) // add 0x20 to get first id after length
              amountPos := add(amountPos, 0x20) // add 0x20 to get first amount after length

              subBalanceOf(
                from,
                calldataload(idPos),
                calldataload(amountPos)
              )

              addBalanceOf(
                to,
                calldataload(idPos),
                calldataload(amountPos)
              )
          }

          emitTransferBatch(caller(), from, to, idsStartPos, idsLength, amountsStartPos, amountsLength)

          _doBatchSafeTransferAcceptanceCheck(caller(), from, to, idsStartPos, idsLength, amountsLength)
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

          let idPos := idsStartPos
          let amountPos := amountsStartPos

          for { let i := 0 } lt(i, idsLength) { i := add(i, 0x01) } {
              idPos := add(idPos, 0x20) // add 0x20 to get first id after length
              amountPos := add(amountPos, 0x20) // add 0x20 to get first amount after length

              addBalanceOf(
                to,
                calldataload(idPos),
                calldataload(amountPos)
              )
          }

          emitTransferBatch(caller(), 0x0, to, idsStartPos, idsLength, amountsStartPos, amountsLength)

          _doBatchSafeTransferAcceptanceCheck(caller(), 0x0, to, idsStartPos, idsLength, amountsLength)
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

      function _batchBurn() {
          let from := decodeAsAddress(0)
          notZeroAddress(from)

          let idsOffset := decodeAsUint(1)
          let amountsOffset := decodeAsUint(2)

          let idsStartPos := add(idsOffset, 0x04)
          let idsLength := calldataload(idsStartPos)

          let amountsStartPos := add(amountsOffset, 0x04)
          let amountsLength := calldataload(amountsStartPos)

          require(eq(idsLength, amountsLength))

          let idPos := idsStartPos
          let amountPos := amountsStartPos

          for { let i := 0 } lt(i, idsLength) { i := add(i, 0x01) } {
              idPos := add(idPos, 0x20) // add 0x20 to get first id after length
              amountPos := add(amountPos, 0x20) // add 0x20 to get first amount after length

              subBalanceOf(
                from,
                calldataload(idPos),
                calldataload(amountPos)
              )
          }

          emitTransferBatch(caller(), from, 0x0, idsStartPos, idsLength, amountsStartPos, amountsLength)
      }

      function _doBatchSafeTransferAcceptanceCheck(operator, from, to, idsStartPos, idsLength, amountsLength) {
          if isContract(to) {
              let onERC1155BatchReceivedSelector := 0xbc197c8100000000000000000000000000000000000000000000000000000000

              mstore(0, onERC1155BatchReceivedSelector)
              mstore(0x04, operator)
              mstore(0x24, from)
              mstore(0x44, 0xa0) // 1st offset will be 5th word of calldata because 2 addresses + 2 uint array + 1 data
              mstore(0x64, add(0xc0, mul(idsLength, 0x20))) // offset for 2nd array
              mstore(0x84, add(0xe0, mul(add(idsLength, amountsLength), 0x20))) // offset for data
              calldatacopy(0xa4, idsStartPos, sub(calldatasize(), idsStartPos)) // idsStartPos == 0x84 (after selectors + 1 x addr + 3 x offset)

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

      function emitTransferBatch(operator, from, to, idsStartPos, idsLength, amountsStartPos, amountsLength) {
          mstore(0, 0x40) // offset for ids
          mstore(0x20, add(0x60, mul(idsLength, 0x20))) // offset for amounts
          calldatacopy(0x40, idsStartPos, mul(add(idsLength, 0x01), 0x20)) // copy ids length and array elements. +1 to include length
          calldatacopy(add(0x40, mul(add(idsLength, 0x01), 0x20)), amountsStartPos, mul(add(amountsLength, 0x01), 0x20)) // copy amounts length and array elements. +1 to include length
          let eventLength := add(add(idsLength, amountsLength), 4)

          log4(
              0x00, // Memory location where non-indexed args are stored
              mul(eventLength, 0x20),
              0x4a39dc06d4c0dbc64b70af90fd698a233a518aa5d07e595d983b8c0526c8f7fb /* keccak "TransferBatch(address,address,address,uint256[],uint256[])" */,
              operator, // indexed arg
              from, // indexed arg
              to // indexed arg
          )
      }

      function emitApprovalForAll(owner, operator, approved) {
          mstore(0, approved)
          log3(
              0x00, // Memory location where non-indexed args are stored
              0x20,
              0x17307eab39ab6107e8899845ad3d59bd9653f200f220920489ca2b5937696c31 /* keccak "ApprovalForAll(address,address,bool)" */,
              owner, // indexed arg
              operator // indexed arg
          )
      }
    }
  }
}
