final captureTemplateNameContractCases =
    <({String label, String input, String normalized, String key})>[
      (
        label: 'collapsed ASCII whitespace',
        input: '  日常   巡检  ',
        normalized: '日常 巡检',
        key: '日常 巡检',
      ),
      (label: 'ASCII upper case', input: 'ABC', normalized: 'ABC', key: 'abc'),
      (label: 'ASCII lower case', input: 'abc', normalized: 'abc', key: 'abc'),
      (
        label: 'mixed script upper case',
        input: '模板A',
        normalized: '模板A',
        key: '模板a',
      ),
      (
        label: 'mixed script lower case',
        input: '模板a',
        normalized: '模板a',
        key: '模板a',
      ),
      (
        label: 'U+0085 edge trim and internal preservation',
        input: '\u0085A\u0085B\u0085',
        normalized: 'A\u0085B',
        key: 'a\u0085b',
      ),
      (
        label: 'U+FEFF edge trim and internal collapse',
        input: '\uFEFFA\uFEFFB\uFEFF',
        normalized: 'A B',
        key: 'a b',
      ),
      (
        label: 'U+200B preservation',
        input: '\u200BA\u200BB\u200B',
        normalized: '\u200BA\u200BB\u200B',
        key: '\u200Ba\u200Bb\u200B',
      ),
    ];

final captureTemplate80Scalars = '😀' * 80;
final captureTemplate81Scalars = '😀' * 81;

final captureTemplateNulFieldCases =
    <
      ({
        String label,
        String name,
        String workLocation,
        String workContent,
        String photographer,
      })
    >[
      (
        label: 'name',
        name: '模\u0000板',
        workLocation: 'A 区',
        workContent: '检查',
        photographer: '张工',
      ),
      (
        label: 'workLocation',
        name: '模板-部位-NUL',
        workLocation: 'A\u0000区',
        workContent: '检查',
        photographer: '张工',
      ),
      (
        label: 'workContent',
        name: '模板-内容-NUL',
        workLocation: 'A 区',
        workContent: '检\u0000查',
        photographer: '张工',
      ),
      (
        label: 'photographer',
        name: '模板-拍摄人-NUL',
        workLocation: 'A 区',
        workContent: '检查',
        photographer: '张\u0000工',
      ),
    ];
