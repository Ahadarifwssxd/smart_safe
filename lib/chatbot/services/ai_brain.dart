import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../theme/colors.dart';
import '../models/chat_models.dart';
import 'chatbot_faq_service.dart';

class AIBrain {
  // ── Process user input and return bot response ───────────────
  // [history] = the conversation so far (older→newer) so the AI has memory and
  // can answer follow-ups in context. Urgent safety queries skip the network and
  // answer instantly from the local brain.
  static Future<List<ChatMsg>> respond(String input,
      {List<ChatMsg> history = const []}) async {
    final q = input.toLowerCase().trim();

    // 0. Admin-managed FAQ (dashboard-editable) wins — lets the team add or
    // override answers without a new app build.
    final faqAnswer = ChatbotFaqService.instance.match(q);
    if (faqAnswer != null && faqAnswer.trim().isNotEmpty) {
      return [ChatMsg.bot(faqAnswer)];
    }

    // 1. Try Live Groq API first (if input is not a direct urgent safety keyword)
    final isUrgentSafetyQuery = _isUrgentSafety(q);
    if (!isUrgentSafetyQuery) {
      try {
        const apiKey = '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';
        final responseText = await _queryGroq(input, apiKey, history)
            .timeout(const Duration(seconds: 12));
        if (responseText.isNotEmpty) {
          return [ChatMsg.bot(responseText)];
        }
      } catch (e) {
        debugPrint('Groq API Error: $e');
        // Fallback to local processing on API failure / timeout.
      }
    }

    // 2. Local Processing (Fuzzy/Keyword matching offline brain)
    await Future.delayed(const Duration(milliseconds: 600)); // natural typing delay

    // ── SOS / Emergency trigger ──────────────────────────────
    if (_has(q, ['sos', 'emergency', 'help', 'danger', 'trigger', 'khatra', 'madad', 'bachao', 'musibat'])) {
      return [
        ChatMsg.bot(
          '🆘 SOS can be triggered 3 ways / SOS trigger karne ke 3 tareeqe hain:',
          emergency: true,
          replies: ['Show me more', 'Call 1122 now', 'Women safety'],
          card: ChatCard(
            title: 'Trigger SOS Instantly',
            body: '1. Tap the big red SOS button on Home\n2. Shake your phone 3 times\n3. Press Volume Up + Down buttons together',
            icon: Icons.warning_amber_rounded,
            color: C.red,
            actionLabel: 'Go to Home',
          ),
        ),
      ];
    }

    // ── Crash detection ──────────────────────────────────────
    if (_has(q, ['crash', 'accident', 'car', 'vehicle', 'gaari', 'thuk', 'takkar', 'chot'])) {
      return [
        ChatMsg.bot(
          '🚗 SmartSafe auto-detects crashes using your phone\'s accelerometer!\n\nImpact detected → 10-sec cancel window → GPS sent to contacts → 1122 auto-dialed.',
          replies: ['Turn it on', 'Test crash detection', 'What happens after?'],
          card: const ChatCard(
            title: 'Crash Detection Flow',
            body: 'SmartSafe crash detection uses advanced algorithms to keep you safe in vehicle emergencies.',
            icon: Icons.car_crash_rounded,
            color: Color(0xFFF4A261),
          ),
        ),
      ];
    }

    // ── Safe route ───────────────────────────────────────────
    if (_has(q, ['route', 'safe route', 'road', 'path', 'navigate', 'direction', 'map', 'rasta', 'sarak'])) {
      return [
        ChatMsg.bot(
          '🛡️ Safe Route shows you the safest path to your destination!\n\n🟢 Green = Safe\n🟡 Amber = Caution\n🔴 Red = Avoid',
          replies: ['Night travel tips', 'Open safe route', 'Driving safety'],
        ),
      ];
    }

    // ── Contacts ─────────────────────────────────────────────
    if (_has(q, ['contact', 'add contact', 'trusted', 'circle', 'family', 'notified', 'dost', 'rishtedar'])) {
      return [
        ChatMsg.bot(
          '👥 Your Trusted Circle can have up to 5 people. They get instant SMS + app alerts when you trigger SOS.\n\nTo add: Go to People tab → tap \'Add\' button ➕',
          replies: ['How many contacts?', 'SMS or app alert?', 'Go to contacts'],
        ),
      ];
    }

    // ── Women safety ─────────────────────────────────────────
    if (_has(q, ['women', 'girl', 'harassment', 'stalking', 'unsafe', 'follow', 'stranger', 'rape', 'assault', 'larki', 'harras', 'picha'])) {
      return [
        ChatMsg.bot(
          '👩 Women Safety Guide & Tips / Khawateen ki Hifazat:\n\n• Cross the street immediately if followed\n• Enter a shop or public place\n• Shake phone 3× for silent SOS',
          emergency: true,
          replies: ['Self-defense tips', 'Pakistan helplines', 'Warning signs'],
          card: const ChatCard(
            title: '⚠️ If Followed / Agar Koi Picha Kare',
            body: 'Scream loudly, go to a crowded place, and activate silent SOS immediately.',
            icon: Icons.woman_rounded,
            color: Color(0xFF6C63FF),
          ),
        ),
      ];
    }

    // ── Self defense ─────────────────────────────────────────
    if (_has(q, ['self defense', 'defend', 'fight', 'protect', 'attack', 'hifazat', 'bachao'])) {
      return [
        ChatMsg.bot(
          '🥊 Basic self-defense points:\n\n👁️ Eyes — jab fingers\n👃 Nose — palm strike upward\n🗣️ Throat — strike hard\n\n⚡ Run and scream "FIRE!" immediately.',
          replies: ['More safety tips', 'What to carry', 'Women safety page'],
        ),
      ];
    }

    // ── First aid ────────────────────────────────────────────
    if (_has(q, ['first aid', 'bleeding', 'burn', 'cpr', 'heart', 'choking', 'fracture', 'broken', 'injured', 'wound', 'khoon', 'zakhmi', 'haddi'])) {
      if (_has(q, ['bleed', 'blood', 'cut', 'wound', 'khoon'])) {
        return [
          ChatMsg.bot(
            '🩸 Heavy Bleeding — Act Fast / Khoon Bahna:\n\n1. Press HARD with clean cloth\n2. Raise the limb above heart level\n3. Call 1122 immediately',
            emergency: true,
            replies: ['CPR steps', 'Burns treatment', 'Call 1122'],
          ),
        ];
      }
      if (_has(q, ['cpr', 'heart', 'breathing', 'unconscious', 'dil'])) {
        return [
          ChatMsg.bot(
            '❤️ CPR Steps:\n\n1. Call 1122 FIRST\n2. 30 chest compressions (push 5-6cm deep)\n3. 2 rescue breaths\n4. Speed: 100-120 compressions/minute',
            emergency: true,
            replies: ['Choking help', 'Burns treatment', 'Open First Aid guide'],
          ),
        ];
      }
      return [
        ChatMsg.bot(
          '🩺 First Aid Guide covers CPR, Bleeding, Burns, Choking, and Fractures.\n\nChoose a topic below to learn step-by-step instructions.',
          replies: ['CPR', 'Bleeding', 'Burns', 'Choking'],
        ),
      ];
    }

    // ── Emergency numbers ────────────────────────────────────
    if (_has(q, ['number', 'helpline', 'call', 'phone', '1122', '15', '1099', 'edhi', 'police', 'ambulance', 'fire'])) {
      return [
        ChatMsg.bot(
          '📞 Pakistan Emergency Numbers:\n\n🚑 1122 — Ambulance (Rescue)\n👮 15 — Police Emergency\n💜 1099 — Madadgar (Women & Child)\n🟢 115 — Edhi Foundation',
          replies: ['Call 1122', 'Open emergency dial', 'Nearest hospitals'],
          card: const ChatCard(
            title: 'Most Important Numbers',
            body: 'Save these offline:\n1122 · 15 · 1099 · 115',
            icon: Icons.call_rounded,
            color: Color(0xFF2EC4B6),
          ),
        ),
      ];
    }

    // ── Panic toolkit ────────────────────────────────────────
    if (_has(q, ['panic', 'toolkit', 'siren', 'alarm', 'flashlight', 'torch', 'fake call', 'loud', 'noise', 'shor'])) {
      return [
        ChatMsg.bot(
          '🔦 Panic Toolkit has 4 tools:\n\n🔦 Flashlight (blind attacker)\n📢 Alarm Siren (attract attention)\n📱 Fake Call (simulate call)\n⏱️ Distress Timer (auto SOS)',
          replies: ['How to use siren?', 'What is fake call?', 'Open panic toolkit'],
        ),
      ];
    }

    // ── GPS / Location ───────────────────────────────────────
    if (_has(q, ['gps', 'location', 'track', 'live', 'share', 'map', 'jagah'])) {
      return [
        ChatMsg.bot(
          '📍 SmartSafe shares your GPS location with trusted contacts every 3 seconds when SOS is active. Accurate to ±4 meters and works in the background.',
          replies: ['Open live map', 'How accurate?', 'Who can see my location?'],
        ),
      ];
    }

    // ── Check-in ─────────────────────────────────────────────
    if (_has(q, ['check in', 'checkin', 'timer', 'arrive', 'safe arrival', 'arrive safe'])) {
      return [
        ChatMsg.bot(
          '⏱️ Safe Check-In:\n\n1. Set a timer (10–120 mins)\n2. Arrive at destination and press "I\'m Safe"\n3. If you don\'t, SOS is sent automatically to contacts.',
          replies: ['Set 30 min timer', 'How to use?', 'Open check-in'],
        ),
      ];
    }

    // ── Greetings ────────────────────────────────────────────
    if (_has(q, ['hi', 'hello', 'hey', 'salam', 'assalam', 'aoa', 'helo', 'hii', 'shuroo', 'start'])) {
      return [
        ChatMsg.bot(
          'Assalam u Alaikum! 👋 I\'m SafeBot — your personal safety assistant!\n\nMain aapki madad kar sakta hoon:\n🆘 Emergency help\n🛡️ Safety tips\n🩺 First aid\n\nAap kya jaanna chahte hain?',
          replies: ['How to use SOS?', 'Women safety tips', 'Emergency numbers', 'First aid help'],
        ),
      ];
    }

    if (_has(q, ['who are you', 'what are you', 'bot', 'ai', 'robot', 'chatbot', 'safebot'])) {
      return [
        ChatMsg.bot(
          '🤖 Main SafeBot hoon — SmartSafe ka AI safety assistant!\n\nMain trained hoon:\n• Pakistan safety laws\n• Emergency procedures\n• SmartSafe app features\n• First aid guidance\n• Women & child safety\n\nMain 24/7 available hoon. Koi bhi safety sawaal puchein!',
          replies: ['What can you do?', 'Emergency help', 'Safety tips'],
        ),
      ];
    }

    // ── Thanks ───────────────────────────────────────────────
    if (_has(q, ['thank', 'thanks', 'shukriya', 'shukria', 'great', 'good', 'helpful', 'perfect'])) {
      return [
        ChatMsg.bot(
          'Shukriya! 😊 Stay safe and keep SmartSafe active always.\n\nYaad rakhein:\n• Phone charged rakhen\n• Trusted contacts add karen\n• Night travel se pehle route check karen\n\nKoi aur sawaal ho toh batayein! 🛡️',
          replies: ['More safety tips', 'Emergency numbers', 'Open home'],
        ),
      ];
    }

    // ── Fallback ─────────────────────────────────────────────
    return [
      ChatMsg.bot(
        'Maafi chahta hoon, main samajh nahi paya. 🤔\n\nYeh topics par madad kar sakta hoon:',
        replies: [
          'SOS & Emergency',
          'Women safety',
          'First aid',
          'Emergency numbers',
          'App features',
          'Safety tips',
        ],
      ),
    ];
  }

  static bool _has(String text, List<String> keywords) =>
    keywords.any((k) => text.contains(k));

  static bool _isUrgentSafety(String text) {
    const urgentKeywords = [
      'sos', 'emergency', 'help me', 'danger', 'khatra', 'madad', 'bachao',
      'musibat', 'accident', 'crash', 'thuk', 'takkar', 'harassment',
      'stalking', 'follow', 'rape', 'assault', 'bleed', 'blood', 'cpr',
      'choking', 'helpline', '1122', '15', 'police', 'ambulance',
    ];
    return urgentKeywords.any((k) => text.contains(k));
  }

  static Future<String> _queryGroq(
      String prompt, String apiKey, List<ChatMsg> history) async {
    final url = Uri.parse('https://api.groq.com/openai/v1/chat/completions');

    final messages = <Map<String, dynamic>>[];
    
    // System instructions
    messages.add({
      'role': 'system',
      'content': 'You are SafeBot, a calm, empathetic AI safety assistant built into the '
          'SmartSafe personal-safety app in Pakistan. '
          'App features you can guide users on: SOS triggers (tap the red SOS button, '
          'shake the phone 3 times, or press Volume Up+Down together), Crash Detection, '
          'Safe Route (safest path scored against flagged danger zones), Panic Toolkit '
          '(siren, flashlight, fake call, distress timer), Trusted Contacts (up to 5, who '
          'get SMS + app alerts on SOS), Women Safety guide, First Aid guide, Safe Check-In, '
          'and Pakistan emergency numbers (1122 Ambulance, 15 Police, 1099 Madadgar, 115 Edhi). '
          'RULES: 1) Safety first — if the user seems in real danger, tell them to tap SOS or '
          'call 1122/15 immediately, briefly, before anything else. '
          '2) Be concise and actionable — short paragraphs or bullet points, no fluff. '
          '3) Remember the conversation and answer follow-ups in context. '
          '4) Match the user\'s language: reply in Roman Urdu/Urdu if they write that way, '
          'English if they write English. '
          '5) Only answer safety, health, and SmartSafe-app questions; gently redirect off-topic asks.'
    });

    final recent =
        history.length > 10 ? history.sublist(history.length - 10) : history;
    for (final m in recent) {
      if (m.text.trim().isEmpty) continue;
      messages.add({
        'role': m.from == MsgFrom.user ? 'user' : 'assistant',
        'content': m.text,
      });
    }

    messages.add({
      'role': 'user',
      'content': prompt,
    });

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': 'llama-3.3-70b-versatile',
        'messages': messages,
        'temperature': 0.7,
        'max_tokens': 500,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final choices = data['choices'] as List?;
      if (choices != null && choices.isNotEmpty) {
        final message = choices[0]['message'];
        if (message != null) {
          return message['content'] ?? '';
        }
      }
    } else {
      debugPrint('Groq API returned status code ${response.statusCode}: ${response.body}');
    }
    return '';
  }
}
