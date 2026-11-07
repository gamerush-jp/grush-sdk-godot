extends RefCounted

const CODE_NONE := ""
const CODE_UNSUPPORTED := "unsupported"
const CODE_UNAVAILABLE := "unavailable"
const CODE_TIMEOUT := "timeout"
const CODE_RATE_LIMITED := "rateLimited"
const CODE_SIGN_IN_REQUIRED := "signInRequired"
const CODE_CONSENT_DECLINED := "consentDeclined"
const CODE_INVALID_PARAMS := "invalidParams"
## 確認用の表示（[code]GRush.player_state.preview_received[/code]）を購読していないので、他のプレイヤーの公開プレイヤー状態を読めない。
const CODE_PREVIEW_REQUIRED := "previewRequired"
const CODE_INTERNAL := "internal"


static func ok(value: Variant) -> Dictionary:
	return {"ok": true, "value": value, "code": CODE_NONE, "message": ""}


static func failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "value": null, "code": code, "message": message}


static func unsupported() -> Dictionary:
	return failure(CODE_UNSUPPORTED, "GameRush GameAPI is not available here.")


static func map_code(code: String) -> String:
	match code:
		"unsupportedMethod":
			return CODE_UNSUPPORTED
		CODE_UNAVAILABLE, CODE_TIMEOUT, CODE_RATE_LIMITED:
			return code
		CODE_SIGN_IN_REQUIRED, CODE_CONSENT_DECLINED, CODE_INVALID_PARAMS:
			return code
		CODE_PREVIEW_REQUIRED:
			return code
		_:
			return CODE_INTERNAL
