/// App 内「自带大脑」的**规范层**（v0.4.35，移植自 dsh-brain 的 `role.js`）。
///
/// 定位：规范是**人与领域**的静态约定（"这个 App 是干什么的、怎么答、红线在哪"），
/// 和「角色」（模型从对话里长出来的自我定义）是两层东西：
/// - 规范：稳定、可审阅、由用户写；放 system prompt；
/// - 角色：慢变、由模型写；session 首次整理后 bootstrap（见 character_service）。
///
/// 这里只存一段自由文本（用户自己写规矩），渲染成固定标题的段落注入。
/// 结构化字段（domain/title/rules/红线条目）留到后面需要时再拆——先把"能写、能注入、
/// 能验证"这条路打通。
library;

/// 注入段的标题（测试与文档共用这一个常量，别在两处写死）。
const String kSpecialtySectionTitle = '【专业规范】';

/// 默认截断长度：规范是自己写的，太长会挤掉别的段。
const int kSpecialtyMaxChars = 1200;

/// 把「专业规范」文本渲染成注入段（纯函数）。
///
/// - 空 / 全空白 → 返回空串（不注入、不占 token）；
/// - 去掉首尾空白，保留内部换行（用户可能写条目）；
/// - 超过 [maxChars] 截断并加省略号。
String renderSpecialtySection(String? rules, {int maxChars = kSpecialtyMaxChars}) {
  final text = (rules ?? '').trim();
  if (text.isEmpty) return '';
  final limit = maxChars < 32 ? 32 : maxChars;
  final value = text.length <= limit ? text : '${text.substring(0, limit - 1)}…';
  return '$kSpecialtySectionTitle\n$value';
}
