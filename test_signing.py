from web3 import Web3
from eth_account import Account

print('Web3 version:', Web3.__version__)

# Test the actual signing
w3 = Web3()
dummy_key = '0x' + '1' * 64
account = Account.from_key(dummy_key)
transaction = {
    'to': '0x' + '0' * 40,
    'value': 0,
    'gas': 21000,
    'gasPrice': 1000000000,
    'nonce': 0
}

signed_txn = w3.eth.account.sign_transaction(transaction, private_key=dummy_key)
print('SignedTransaction type:', type(signed_txn))
print('Available attributes:', [attr for attr in dir(signed_txn) if not attr.startswith('_')])
print('Has raw_transaction:', hasattr(signed_txn, 'raw_transaction'))
print('Has rawTransaction:', hasattr(signed_txn, 'rawTransaction'))

# Test accessing the attribute
try:
    data = signed_txn.raw_transaction
    print('✅ raw_transaction works, length:', len(data))
except AttributeError as e:
    print('❌ raw_transaction failed:', e)

try:
    data = signed_txn.rawTransaction
    print('✅ rawTransaction works, length:', len(data))
except AttributeError as e:
    print('❌ rawTransaction failed:', e) 