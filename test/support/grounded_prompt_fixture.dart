// Test-double reader only. Never used to select production evidence or citations.
List<String> groundedFixturePassages(String prompt) =>
    RegExp(r'<passage>([\s\S]*?)</passage>')
        .allMatches(prompt)
        .map(
          (match) => match
              .group(1)!
              .replaceAll('&lt;', '<')
              .replaceAll('&gt;', '>')
              .replaceAll('&amp;', '&'),
        )
        .toList();
