import 'package:flutter/material.dart';

import '../core/calculator.dart';
import 'theme.dart';

/// Icons and colours that help people find their way. They carry no meaning
/// about good or bad; those colours stay reserved for results.

const Map<Question, IconData> questionIcons = {
  Question.afford: Icons.home_outlined,
  Question.loanCost: Icons.account_balance_outlined,
  Question.later: Icons.savings_outlined,
  Question.worthIt: Icons.trending_up_rounded,
  Question.takeHome: Icons.receipt_long_outlined,
  Question.quick: Icons.bolt_rounded,
};

/// A distinct, calm hue per question group, so the six groups can be told
/// apart at a glance. Light and dark pairs are tuned for contrast separately.
Hue questionHue(BuildContext context, Question q) {
  final dark = context.isDark;
  return switch (q) {
    Question.afford =>
      dark
          ? const Hue(Color(0xFF14312A), Color(0xFF6FD1AE))
          : const Hue(Color(0xFFE2F2EB), Color(0xFF0F6E52)),
    Question.loanCost =>
      dark
          ? const Hue(Color(0xFF172638), Color(0xFF8DB8F2))
          : const Hue(Color(0xFFE5EEFA), Color(0xFF2B5C9E)),
    Question.later =>
      dark
          ? const Hue(Color(0xFF241E36), Color(0xFFB9A2EC))
          : const Hue(Color(0xFFEEE9F9), Color(0xFF6445A8)),
    Question.worthIt =>
      dark
          ? const Hue(Color(0xFF30260F), Color(0xFFE3B458))
          : const Hue(Color(0xFFFBF0DC), Color(0xFF8E5B0B)),
    Question.takeHome =>
      dark
          ? const Hue(Color(0xFF331A22), Color(0xFFEE98AC))
          : const Hue(Color(0xFFFBE8EC), Color(0xFF9F3651)),
    Question.quick =>
      dark
          ? const Hue(Color(0xFF1C2328), Color(0xFFA9BBC8))
          : const Hue(Color(0xFFE9EEF2), Color(0xFF465766)),
  };
}

const Map<String, IconData> _calculatorIcons = {
  'affordability': Icons.home_work_outlined,
  'mortgage': Icons.calendar_month_outlined,
  'hdb_vs_bank': Icons.compare_arrows_rounded,
  'refinance': Icons.autorenew_rounded,
  'credit_card': Icons.credit_card_outlined,
  'personal_loan': Icons.request_quote_outlined,
  'car_loan': Icons.directions_car_outlined,
  'cpf_projection': Icons.account_balance_wallet_outlined,
  'savings_growth': Icons.savings_outlined,
  'tvm': Icons.timeline_rounded,
  'roi': Icons.percent_rounded,
  'average_cost': Icons.candlestick_chart_outlined,
  'fund_fees': Icons.pie_chart_outline_rounded,
  'income_tax': Icons.receipt_long_outlined,
  'stamp_duty': Icons.approval_outlined,
  'percentage': Icons.percent_rounded,
  'rule_72': Icons.hourglass_bottom_rounded,
  'gst': Icons.sell_outlined,
  'bill_split': Icons.restaurant_outlined,
};

IconData calculatorIcon(Calculator c) =>
    _calculatorIcons[c.id] ?? questionIcons[c.question] ?? Icons.calculate;

/// Extra words people search with that do not appear in a calculator's name,
/// so "house" finds affordability and "tax" finds stamp duty.
const Map<String, String> calculatorKeywords = {
  'affordability': 'house home property buy flat condo hdb tdsr msr ltv budget',
  'mortgage': 'home loan housing instalment monthly repayment schedule',
  'hdb_vs_bank': 'hdb concessionary bank package housing loan',
  'refinance': 'reprice switch bank lock-in penalty mortgage',
  'credit_card': 'debt minimum payment interest card',
  'personal_loan': 'flat rate eir effective interest bank loan',
  'car_loan': 'vehicle coe rule of 78 early settlement hire purchase',
  'cpf_projection': 'cpf oa sa ma ra retirement medisave bhs frs',
  'savings_growth': 'deposit interest bank account compound save',
  'tvm': 'present value future value annuity npv pmt',
  'roi': 'return profit gain investment annualised cagr',
  'average_cost': 'shares stocks sgx buy more break even',
  'fund_fees': 'expense ratio ilp unit trust robo portfolio charges',
  'income_tax': 'iras tax relief salary bonus',
  'stamp_duty': 'bsd absd property tax iras buyer',
  'percentage': 'percent change discount increase',
  'rule_72': 'double doubling years',
  'gst': 'goods services tax price 9%',
  'bill_split': 'restaurant service charge share friends',
};

/// A friendly greeting for the local time of day.
String greetingFor(DateTime now) {
  final h = now.hour;
  if (h < 5) return 'Good evening';
  if (h < 12) return 'Good morning';
  if (h < 18) return 'Good afternoon';
  return 'Good evening';
}
