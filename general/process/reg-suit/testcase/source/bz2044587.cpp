#include <QProcess>
#include <QCoreApplication>
#include <cstdio>


int main(int argc, char ** argv)
{
    QProcess process(0);

    process.setProcessEnvironment(QProcessEnvironment::systemEnvironment());
    process.setStandardInputFile(argv[1]);

    process.start("/usr/bin/tee", QStringList(QString(argv[2])));
    process.waitForFinished();
}
