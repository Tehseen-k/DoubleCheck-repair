import 'dart:async';

import 'package:doublecheck_repairs/config/app_config.dart';
import 'package:doublecheck_repairs/services/google_auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class OtpRegistrationSheet extends StatefulWidget {
  const OtpRegistrationSheet({
    super.key,
    required this.email,
    required this.onVerify,
    required this.onResend,
    required this.onDismiss,
  });

  final String email;
  final Future<OtpVerifyResult> Function(String otp) onVerify;
  final Future<void> Function() onResend;
  final Future<void> Function() onDismiss;

  @override
  State<OtpRegistrationSheet> createState() => _OtpRegistrationSheetState();
}

class _OtpRegistrationSheetState extends State<OtpRegistrationSheet> {
  final _otpController = TextEditingController();
  final _focusNode = FocusNode();

  bool _isVerifying = false;
  bool _isResending = false;
  String? _errorMessage;

  @override
  void dispose() {
    _otpController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6 || _isVerifying) return;

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    try {
      final result = await widget.onVerify(otp);
      if (!mounted) return;

      switch (result) {
        case OtpVerifyResult.success:
          Navigator.of(context).pop();
        case OtpVerifyResult.invalidOtp:
          setState(() {
            _errorMessage = 'Invalid code, please try again';
            _otpController.clear();
          });
          _focusNode.requestFocus();
        case OtpVerifyResult.error:
          setState(() {
            _errorMessage = 'Something went wrong, please try again';
          });
      }
    } finally {
      if (mounted) {
        setState(() => _isVerifying = false);
      }
    }
  }

  Future<void> _resend() async {
    if (_isResending || _isVerifying) return;

    setState(() {
      _isResending = true;
      _errorMessage = null;
    });

    try {
      await widget.onResend();
      if (!mounted) return;
      _otpController.clear();
      _focusNode.requestFocus();
    } finally {
      if (mounted) {
        setState(() => _isResending = false);
      }
    }
  }

  Future<void> _dismiss() async {
    await widget.onDismiss();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _onOtpChanged(String value) {
    if (value.length == 6 && !_isVerifying) {
      unawaited(_verify());
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              onPressed: _isVerifying ? null : _dismiss,
              icon: const Icon(Icons.close),
              tooltip: 'Dismiss',
            ),
          ),
          Text(
            'Check your email',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'We sent a 6-digit code to ${widget.email}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.black54,
                ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _otpController,
            focusNode: _focusNode,
            enabled: !_isVerifying,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 6,
            style: const TextStyle(
              fontSize: 24,
              letterSpacing: 8,
              fontWeight: FontWeight.w600,
            ),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              counterText: '',
              hintText: '000000',
              errorText: _errorMessage,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: _onOtpChanged,
            onSubmitted: (_) => _verify(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: _isVerifying ? null : _verify,
              style: FilledButton.styleFrom(
                backgroundColor: AppConfig.brandColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isVerifying
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Verify',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: (_isVerifying || _isResending) ? null : _resend,
            child: _isResending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Resend code'),
          ),
        ],
      ),
    );
  }
}
