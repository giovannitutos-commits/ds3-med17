# FrenchDiag iOS — instalação para testes

Este artefato é uma compilação para iPhone ARM64, sem assinatura. Não é um build de simulador e não instala diretamente por Diawi, Safari ou TestFlight.

1. Baixe o artefato `FrenchDiag-iOS-Unsigned-IPA` da execução aprovada em GitHub Actions e extraia o ZIP.
2. No Windows, baixe Sideloadly do site oficial https://sideloadly.io/ e instale os componentes Apple solicitados por ele.
3. Conecte o iPhone por USB e confirme “Confiar neste computador”.
4. Abra o IPA no Sideloadly, selecione o iPhone e autentique sua conta Apple gratuita **no Sideloadly**. Não compartilhe a senha em chats ou no repositório.
5. Instale. Quando solicitado pelo sistema, confie no perfil pessoal em Ajustes → Geral → VPN e Gerenciamento de Dispositivo.
6. Em iOS 16 ou posterior, ative Modo Desenvolvedor em Ajustes → Privacidade e Segurança, se necessário, e reinicie conforme instrução do sistema.
7. A assinatura gratuita expira após 7 dias; renove pelo Sideloadly. O aplicativo em si não tem validade ou código de liberação.

Na primeira execução, configure Wi-Fi ou BLE, selecione o perfil da ECU e permita Rede Local/Bluetooth. Para Wi-Fi, conecte previamente o iPhone à rede do adaptador.

Liquid Glass usa a API nativa no iOS 26+. Compatibilidade mínima: iOS 17, com material translúcido do sistema em versões anteriores. Bluetooth serial clássico SPP genérico não é oferecido no iOS. O modo de viagens pede localização somente quando você o inicia.

Os testes automáticos validam respostas gravadas de ECU, catálogo, parser CSV e navegação. Eles não substituem testes com seu iPhone, adaptador e veículo. Consulte FEATURES.md para o estado e as limitações da migração.
