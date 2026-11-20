import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_links.dart';
import '../services/pw_account.dart';
import '../theme.dart';
import '../widgets/svg_icon.dart';

/// OTP login for the user's own Physics Wallah account.
class PwLoginScreen extends StatefulWidget {
  const PwLoginScreen({super.key});

  /// Opens the login page. Completes with true when the account is logged in.
  static Future<bool> open(BuildContext context) async {
    final bool? result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const PwLoginScreen()),
    );
    return result == true;
  }

  @override
  State<PwLoginScreen> createState() => _PwLoginScreenState();
}

class _PwLoginScreenState extends State<PwLoginScreen> {
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _otp = TextEditingController();
  final FocusNode _otpFocus = FocusNode();

  Timer? _timer;
  bool _otpSent = false;
  bool _busy = false;
  int _cooldown = 0;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _otp.dispose();
    _otpFocus.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _cooldown = _cooldown > 0 ? _cooldown - 1 : 0);
      if (_cooldown == 0) timer.cancel();
    });
  }

  Future<void> _sendOtp({required bool whatsapp}) async {
    final String number = PwAccount.cleanPhone(_phone.text);
    if (number.length != 10) {
      setState(() => _error = '10 digit ka mobile number daalein');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await PwAccount.requestOtp(number, whatsapp: whatsapp);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _otpSent = true;
        _notice = whatsapp
            ? 'OTP WhatsApp par bheja gaya (+91 $number)'
            : 'OTP SMS se bheja gaya (+91 $number)';
      });
      _startCooldown();
      _otpFocus.requestFocus();
    } on PwException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'OTP nahi bheja ja saka. $error';
      });
    }
  }

  Future<void> _verify() async {
    final String code = _otp.text.trim();
    if (code.length < 4) {
      setState(() => _error = 'SMS me aaya OTP daalein');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await PwAccount.verifyOtp(_phone.text, code);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on PwException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Login nahi ho paya. $error';
      });
    }
  }

  void _changeNumber() {
    _timer?.cancel();
    _otp.clear();
    setState(() {
      _otpSent = false;
      _cooldown = 0;
      _error = null;
      _notice = null;
    });
  }

  void _useWebsite() {
    AppLinks.openInStudyTab(PwAccount.webLogin);
    Navigator.of(context).pop(false);
  }

  // ------------------------------------------------------------------- ui

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: <Widget>[
            _topBar(),
            const SizedBox(height: 14),
            _introCard(),
            const SizedBox(height: 14),
            _formCard(),
            const SizedBox(height: 14),
            _websiteCard(),
            const SizedBox(height: 14),
            _notesCard(),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return Row(
      children: <Widget>[
        Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(11),
          child: InkWell(
            borderRadius: BorderRadius.circular(11),
            onTap: () => Navigator.of(context).pop(false),
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: AppColors.stroke),
              ),
              child: const AppIcon('back', size: 17),
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'PW account login',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _introCard() {
    return const AppCard(
      padding: EdgeInsets.all(14),
      child: Row(
        children: <Widget>[
          IconBadge('graduation', size: 42, iconSize: 20, gradient: true),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Physics Wallah',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 4),
                Text(
                  'Apne PW number se login karein. Login ke baad PW lecture ka '
                  'link Download tab me daalte hi app use aapke account se '
                  'khol leta hai.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.muted,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _formCard() {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _label('MOBILE NUMBER'),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 13),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.stroke),
                ),
                child: const Text(
                  '+91',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: TextField(
                  controller: _phone,
                  enabled: !_otpSent && !_busy,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  autofillHints: const <String>[
                    AutofillHints.telephoneNumberNational,
                  ],
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  onSubmitted: (_) => _sendOtp(whatsapp: false),
                  style: const TextStyle(
                    fontSize: 15,
                    letterSpacing: 1.2,
                    color: AppColors.text,
                  ),
                  decoration: const InputDecoration(
                    hintText: '10 digit number',
                    fillColor: AppColors.surfaceAlt,
                  ),
                ),
              ),
            ],
          ),
          if (!_otpSent) ...<Widget>[
            const SizedBox(height: 13),
            GradientButton(
              label: 'OTP bhejein',
              icon: 'phone',
              busy: _busy,
              onPressed: _busy ? null : () => _sendOtp(whatsapp: false),
            ),
            const SizedBox(height: 9),
            AppOutlineButton(
              label: 'WhatsApp par OTP',
              icon: 'chat',
              height: 44,
              onPressed: _busy ? null : () => _sendOtp(whatsapp: true),
            ),
          ],
          if (_otpSent) ...<Widget>[
            const SizedBox(height: 15),
            _label('OTP'),
            const SizedBox(height: 8),
            TextField(
              controller: _otp,
              focusNode: _otpFocus,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              autofillHints: const <String>[AutofillHints.oneTimeCode],
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(8),
              ],
              onSubmitted: (_) => _verify(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 19,
                letterSpacing: 7,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
              decoration: const InputDecoration(
                hintText: '••••••',
                fillColor: AppColors.surfaceAlt,
              ),
            ),
            const SizedBox(height: 13),
            GradientButton(
              label: 'Login',
              icon: 'key',
              busy: _busy,
              onPressed: _busy ? null : _verify,
            ),
            const SizedBox(height: 4),
            Row(
              children: <Widget>[
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _busy ? null : _changeNumber,
                      child: const Text(
                        'Number badlein',
                        style: TextStyle(fontSize: 11.5),
                      ),
                    ),
                  ),
                ),
                if (_cooldown > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      'Dobara bhejein: ${_cooldown}s',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.muted,
                      ),
                    ),
                  )
                else
                  TextButton(
                    onPressed:
                        _busy ? null : () => _sendOtp(whatsapp: false),
                    child: const Text(
                      'OTP dobara bhejein',
                      style: TextStyle(fontSize: 11.5),
                    ),
                  ),
              ],
            ),
          ],
          if (_notice != null && _error == null) ...<Widget>[
            const SizedBox(height: 8),
            _message(_notice!, AppColors.success, 'check'),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: 8),
            _message(_error!, AppColors.danger, 'info'),
          ],
        ],
      ),
    );
  }

  Widget _websiteCard() {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text(
            'OTP yahan kaam na kare?',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'PW ki website par login karein — app usi login ko pehchan leta hai.',
            style: TextStyle(fontSize: 10.8, color: AppColors.muted, height: 1.5),
          ),
          const SizedBox(height: 11),
          AppOutlineButton(
            label: 'PW website se login',
            icon: 'browser',
            height: 44,
            onPressed: _busy ? null : _useWebsite,
          ),
        ],
      ),
    );
  }

  Widget _notesCard() {
    const List<List<String>> notes = <List<String>>[
      <String>['shield', 'Number aur OTP sirf PW ke server par jate hain.'],
      <String>['lock', 'Login sirf is phone me save hota hai. Settings se logout kar sakte hain.'],
      <String>[
        'info',
        'DRM-protected lectures download nahi hote — wo PW tab ke player me chalte hain.',
      ],
    ];
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
      child: Column(
        children: notes.map((List<String> note) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: AppIcon(note[0], size: 13, color: AppColors.secondary),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    note[1],
                    style: const TextStyle(
                      fontSize: 10.8,
                      color: AppColors.muted,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _label(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        color: AppColors.muted,
      ),
    );
  }

  Widget _message(String text, Color color, String icon) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: color.withOpacity(0.32)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: AppIcon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 11.5, height: 1.45, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
