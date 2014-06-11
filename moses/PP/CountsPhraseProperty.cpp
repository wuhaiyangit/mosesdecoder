#include "moses/PP/CountsPhraseProperty.h"
#include <sstream>
#include <assert.h>
#include "util/exception.hh"

namespace Moses
{

void CountsPhraseProperty::ProcessValue()
{
  std::istringstream tokenizer(m_value);

  if (! (tokenizer >> m_targetMarginal)) { // first token: countE
    UTIL_THROW2("CountsPhraseProperty: Not able to read target marginal. Flawed property?");
  }
  assert( m_targetMarginal > 0 );

  if (! (tokenizer >> m_sourceMarginal)) { // first token: countF
    UTIL_THROW2("CountsPhraseProperty: Not able to read source marginal. Flawed property?");
  }
  assert( m_sourceMarginal > 0 );

  if (! (tokenizer >> m_jointCount)) { // first token: countEF
    UTIL_THROW2("CountsPhraseProperty: Not able to read joint count. Flawed property?");
  }
  assert( m_jointCount > 0 );

};

} // namespace Moses

