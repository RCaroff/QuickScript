import Darwin

/// Alloue une paire master/slave de pseudo-terminal. Le slave est destiné à être
/// branché sur stdin/stdout/stderr du process enfant ; le master est lu/écrit
/// par l'app parente.
///
/// Le slave est configuré pour ne pas écho-er les saisies (sinon le contenu
/// envoyé via stdin serait re-vu dans l'output) et pour ne pas convertir les
/// `\n` en `\r\n`.
enum PTY {
    static func open() -> (masterFD: Int32, slaveFD: Int32)? {
        let master = posix_openpt(O_RDWR | O_NOCTTY)
        guard master >= 0 else { return nil }

        guard grantpt(master) == 0,
              unlockpt(master) == 0,
              let nameC = ptsname(master) else {
            Darwin.close(master)
            return nil
        }
        let slaveName = String(cString: nameC)
        let slave = Darwin.open(slaveName, O_RDWR | O_NOCTTY)
        guard slave >= 0 else {
            Darwin.close(master)
            return nil
        }

        var term = termios()
        if tcgetattr(slave, &term) == 0 {
            // Pas d'écho : ce qu'on écrit sur stdin du child ne réapparaît pas
            // dans l'output.
            term.c_lflag &= ~tcflag_t(ECHO)
            // Pas de conversion newline en sortie : on garde \n pur.
            term.c_oflag &= ~tcflag_t(ONLCR)
            // Pas de conversion CR → LF en entrée.
            term.c_iflag &= ~tcflag_t(ICRNL)
            tcsetattr(slave, TCSANOW, &term)
        }

        return (master, slave)
    }
}
