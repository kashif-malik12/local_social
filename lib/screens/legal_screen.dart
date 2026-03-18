import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

enum LegalPage { about, terms, privacy }

class LegalScreen extends StatelessWidget {
  final LegalPage page;
  const LegalScreen({super.key, required this.page});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canPop = GoRouter.of(context).canPop();

    return Scaffold(
      appBar: AppBar(
        scrolledUnderElevation: 0,
        leading: canPop
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              )
            : null,
        title: Text(_title),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
            children: _buildContent(context, theme),
          ),
        ),
      ),
    );
  }

  String get _title {
    switch (page) {
      case LegalPage.about:
        return 'About Us';
      case LegalPage.terms:
        return 'Terms & Conditions';
      case LegalPage.privacy:
        return 'Privacy Policy';
    }
  }

  List<Widget> _buildContent(BuildContext context, ThemeData theme) {
    switch (page) {
      case LegalPage.about:
        return _aboutContent(theme);
      case LegalPage.terms:
        return _termsContent(theme);
      case LegalPage.privacy:
        return _privacyContent(theme);
    }
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────

  Widget _h1(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          text,
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
      );

  Widget _h2(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 8),
        child: Text(
          text,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      );

  Widget _body(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: const TextStyle(height: 1.6)),
      );

  Widget _bullet(String text) => Padding(
        padding: const EdgeInsets.only(left: 12, bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 7),
              child: SizedBox(
                width: 6,
                height: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0xFF147A74),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(height: 1.6))),
          ],
        ),
      );

  Widget _divider() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Divider(),
      );

  Widget _contactBox() => Container(
        margin: const EdgeInsets.only(top: 24),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF147A74).withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF147A74).withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Contact',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            SizedBox(height: 6),
            Text('Tradister SAS', style: TextStyle(fontWeight: FontWeight.w600)),
            Text('SIREN: 988 318 945'),
            Text('Ris-Orangis, France'),
            SizedBox(height: 6),
            Text('Email: hello@allonssy.com'),
          ],
        ),
      );

  // ─── About Us ───────────────────────────────────────────────────────────────

  List<Widget> _aboutContent(ThemeData theme) => [
        _h1(theme, 'About Allonssy'),
        _body(
          'Allonssy is a local social platform that connects people within their community — '
          'enabling residents to share, discover, trade, and collaborate with neighbours nearby.',
        ),
        _body(
          'The platform brings together a social feed, a marketplace for buying and selling, '
          'a gig board for local services, food ads, and real-time chat with offer negotiation — '
          'all anchored to where you actually live.',
        ),
        _h2(theme, 'Our Mission'),
        _body(
          'We believe strong communities are built on trust and proximity. Our goal is to make it '
          'genuinely easy to find a trustworthy neighbour, sell something locally, discover a hidden '
          'talent nearby, or simply stay informed about what is happening around you.',
        ),
        _h2(theme, 'The Company'),
        _body(
          'Allonssy is developed and operated by Tradister SAS, a French simplified joint-stock '
          'company (Société par Actions Simplifiée) registered in France.',
        ),
        _bullet('Company name: Tradister SAS'),
        _bullet('SIREN: 988 318 945'),
        _bullet('Registered office: Ris-Orangis, France'),
        _divider(),
        _h2(theme, 'Get in touch'),
        _body(
          'For questions, support, partnership enquiries, or any concern about the platform, '
          'reach us at:',
        ),
        _contactBox(),
      ];

  // ─── Terms & Conditions ──────────────────────────────────────────────────────

  List<Widget> _termsContent(ThemeData theme) => [
        _h1(theme, 'Terms & Conditions'),
        _body('Last updated: March 2026'),
        _body(
          'These Terms & Conditions ("Terms") govern your access to and use of the Allonssy '
          'platform, including the mobile application and website (collectively, the "Service"), '
          'operated by Tradister SAS ("we", "us", or "our").',
        ),
        _body(
          'By creating an account or using the Service you confirm that you have read, understood, '
          'and agree to be bound by these Terms. If you do not agree, do not use the Service.',
        ),
        _h2(theme, '1. Eligibility'),
        _body(
          'You must be at least 16 years of age to create an account and use the Service. '
          'By registering, you represent that you meet this requirement.',
        ),
        _h2(theme, '2. Your Account'),
        _bullet('You are responsible for maintaining the confidentiality of your account credentials.'),
        _bullet('You are responsible for all activity that occurs under your account.'),
        _bullet('You must provide accurate and up-to-date information when registering.'),
        _bullet('You may not transfer or share your account with others.'),
        _bullet('You must notify us immediately at hello@allonssy.com if you suspect unauthorised access.'),
        _h2(theme, '3. Acceptable Use'),
        _body('You agree to use the Service only for lawful purposes. You must not:'),
        _bullet('Post content that is illegal, harmful, abusive, harassing, defamatory, or fraudulent.'),
        _bullet('Use the Service to distribute spam, malware, or unsolicited commercial messages.'),
        _bullet('Impersonate any person or entity or misrepresent your affiliation with any person or entity.'),
        _bullet('Attempt to gain unauthorised access to the Service or its related systems.'),
        _bullet('Scrape, crawl, or systematically extract data from the Service without our written consent.'),
        _bullet('Use the Service to conduct or facilitate illegal transactions.'),
        _h2(theme, '4. User Content'),
        _body(
          'You retain ownership of content you post on Allonssy. By posting content you grant us '
          'a non-exclusive, worldwide, royalty-free licence to use, store, display, reproduce, and '
          'distribute that content solely to operate and improve the Service.',
        ),
        _body(
          'We do not endorse any user-generated content. We reserve the right to remove content '
          'that violates these Terms or that we consider harmful to the community, without notice.',
        ),
        _h2(theme, '5. Marketplace and Transactions'),
        _body(
          'Allonssy provides a platform for users to discover and communicate about local listings. '
          'We are not a party to any transaction between users. We do not guarantee the quality, '
          'safety, legality, or accuracy of any listing. Any transaction you enter into with another '
          'user is solely between you and that user.',
        ),
        _h2(theme, '6. Moderation and Account Suspension'),
        _body(
          'We reserve the right to suspend or terminate accounts that violate these Terms, '
          'engage in fraudulent activity, or harm the community, at our sole discretion and '
          'without prior notice where required by the circumstances.',
        ),
        _h2(theme, '7. Limitation of Liability'),
        _body(
          'To the maximum extent permitted by applicable law, Tradister SAS shall not be liable '
          'for any indirect, incidental, special, consequential, or punitive damages arising from '
          'your use of, or inability to use, the Service.',
        ),
        _h2(theme, '8. Changes to These Terms'),
        _body(
          'We may update these Terms from time to time. We will notify you of significant changes '
          'by posting a notice within the app or by email. Continued use of the Service after '
          'changes take effect constitutes your acceptance of the revised Terms.',
        ),
        _h2(theme, '9. Governing Law'),
        _body(
          'These Terms are governed by and construed in accordance with the laws of France. '
          'Any disputes shall be subject to the exclusive jurisdiction of the courts of France.',
        ),
        _h2(theme, '10. Contact'),
        _body('For questions about these Terms, please contact us:'),
        _contactBox(),
      ];

  // ─── Privacy Policy ──────────────────────────────────────────────────────────

  List<Widget> _privacyContent(ThemeData theme) => [
        _h1(theme, 'Privacy Policy'),
        _body('Last updated: March 2026'),
        _body(
          'Tradister SAS ("we", "us", or "our") operates the Allonssy platform. This Privacy Policy '
          'explains how we collect, use, store, and protect your personal data when you use our '
          'Service, and the rights you have under applicable data protection law, including the '
          'General Data Protection Regulation (GDPR).',
        ),
        _h2(theme, '1. Data Controller'),
        _body(
          'The data controller responsible for your personal data is:\n'
          'Tradister SAS — SIREN 988 318 945 — Ris-Orangis, France\n'
          'Email: hello@allonssy.com',
        ),
        _h2(theme, '2. Data We Collect'),
        _body('We collect the following categories of personal data:'),
        _bullet('Account data: email address, password (hashed), display name, profile photo, city, and postcode.'),
        _bullet('Location data: approximate city/zip-code you set in your profile, used to show you local content. We do not continuously track your device location.'),
        _bullet('Content data: posts, comments, marketplace listings, gig ads, food ads, and chat messages you create.'),
        _bullet('Usage data: app interactions, device type, operating system, and error logs collected for service improvement.'),
        _bullet('Authentication data: if you sign in with Google, we receive your name, email, and profile picture from Google.'),
        _h2(theme, '3. How We Use Your Data'),
        _bullet('To create and manage your account and authenticate you securely.'),
        _bullet('To deliver localised content, listings, and search results relevant to your area.'),
        _bullet('To enable messaging and offer negotiation between users.'),
        _bullet('To send in-app and push notifications based on your preferences.'),
        _bullet('To moderate content, detect fraud, and enforce our Terms & Conditions.'),
        _bullet('To improve the platform through analytics and error reporting.'),
        _h2(theme, '4. Legal Basis for Processing'),
        _bullet('Contract: processing necessary to provide the Service you requested.'),
        _bullet('Legitimate interests: fraud prevention, security, and service improvement.'),
        _bullet('Consent: where you have explicitly opted in (e.g. push notifications).'),
        _h2(theme, '5. Data Sharing'),
        _body(
          'We do not sell your personal data. We may share data with:',
        ),
        _bullet('Infrastructure providers (e.g. hosting and database services) under data processing agreements.'),
        _bullet('Other users: your public profile, posts, and listings are visible to other users as intended by the platform.'),
        _bullet('Law enforcement: if required by applicable law or to protect our legal rights.'),
        _h2(theme, '6. Data Retention'),
        _body(
          'We retain your personal data for as long as your account is active. If you delete '
          'your account, we will delete or anonymise your personal data within 30 days, '
          'except where retention is required by law.',
        ),
        _h2(theme, '7. Your Rights (GDPR)'),
        _body('Under the GDPR you have the following rights:'),
        _bullet('Right of access: request a copy of the personal data we hold about you.'),
        _bullet('Right to rectification: request correction of inaccurate data.'),
        _bullet('Right to erasure: request deletion of your data ("right to be forgotten").'),
        _bullet('Right to restriction: request that we limit how we process your data.'),
        _bullet('Right to data portability: receive your data in a structured, machine-readable format.'),
        _bullet('Right to object: object to processing based on legitimate interests.'),
        _bullet('Right to withdraw consent: withdraw consent at any time without affecting prior processing.'),
        _body(
          'To exercise any of these rights, contact us at hello@allonssy.com. '
          'We will respond within 30 days. You also have the right to lodge a complaint with '
          'your national data protection authority (in France: CNIL — www.cnil.fr).',
        ),
        _h2(theme, '8. Cookies and Tracking'),
        _body(
          'The Allonssy web application may use session cookies for authentication and functional '
          'purposes. We do not use third-party advertising or tracking cookies.',
        ),
        _h2(theme, '9. Security'),
        _body(
          'We apply appropriate technical and organisational measures to protect your personal '
          'data against unauthorised access, loss, or disclosure. All data is transmitted over '
          'encrypted connections (HTTPS/TLS).',
        ),
        _h2(theme, '10. Changes to This Policy'),
        _body(
          'We may update this Privacy Policy from time to time. We will notify you of material '
          'changes by posting a notice within the app or by email. Continued use of the Service '
          'after changes constitutes your acceptance of the updated policy.',
        ),
        _h2(theme, '11. Contact'),
        _body('For any privacy-related questions or to exercise your rights, contact us:'),
        _contactBox(),
      ];
}
